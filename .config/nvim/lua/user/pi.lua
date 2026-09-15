-- pi.lua — inline pi agents inside nvim, with a diff-based accept/reject model.
--
-- Keys (all <leader>g prefixed):
--   <leader>gp  (n/v)  visual: floating prompt; the numbered selection plus the
--                      whole file (@path — injected pre-read by prompt_expansion,
--                      no read round-trip) go to a one-shot agent.
--                      normal: ACCEPT the pending edit under the cursor, or open
--                      the prompt (no selection; agent infers where to edit).
--   <leader>gr  (n)    REJECT the pending edit under the cursor (reverts it).
--   <leader>g]  (n)    jump to the next pending edit; <leader>g[ previous.
--   <leader>gP  (n)    stop the nvim children and open the persistent session
--                      in the pi TUI (tmux split, else :!pi).
--   <leader>gk  (n)    abort streaming children.
--
-- Model: one-shot agents (`pi --mode rpc --no-session --model <fast>` via the
-- scripts/pi wrapper) may gather context with read/bash; their edit/write calls
-- route back over PI_NVIM_SOCKET (pi/extensions/nvim-edit.ts) and are applied
-- through the buffer API. We snapshot the buffer at submit and after every
-- applied edit, so at settle we hold a clean pre→post diff.
--
-- Accept/reject apply that diff to the CURRENT buffer with unix `patch
-- --merge`: the buffer may have drifted (your typing, other concurrent
-- one-shots); collisions surface as standard conflict markers you resolve by
-- hand. No locking, no span bookkeeping — pending hunks carry highlight-only
-- extmarks (they track line drift), and cursor-in-hunk selects the edit.
--   accept: no-op when the buffer already matches post, else forward-patch.
--   reject: exact restore when the buffer matches post, else reverse-patch.
--
-- Accepted edits are recorded into the per-nvim-process persistent session
-- (id nvim-<pid>[-n], created lazily on first accept) as nvim.acceptedEdit
-- custom blocks (instruction + unified diff) via the /nvim-accept extension
-- command — no agent turn. Open that session in the TUI (<leader>gP) and the
-- agent has context for everything accepted in this nvim process.
--
-- Commands: :PiState, :PiEdits, :PiNew, :PiPromptRaw <msg>, :PiStop, :PiAbort.
-- Set PI_NVIM_DEBUG=1 to log RPC traffic to /tmp/pi-nvim-<pid>.log.
local uv = vim.uv or vim.loop
local api = vim.api
local M = {}

local pi_bin = "pi" -- the scripts/pi wrapper: env, APPEND_SYSTEM flags, session dir
local oneshot_model = "zai/glm-5.3-flash" -- fast model; settings map it to low thinking

local ONESHOT_DIRECTIVE = ([[You are making one quick inline edit inside the user's editor.
The file is attached pre-read. Gather extra context with read/bash only when
strictly necessary, then make the edit immediately with the edit tool. Do not
run tests, formatters, or multi-file refactors. Finish with at most one short
sentence.]])

local S = {
    server = nil,
    socket_path = nil,
    zai_key = nil,       -- cached pass secret so children skip the gpg round-trip
    children = {},       -- job id -> child
    by_pid = {},         -- child pid -> child (socket payloads carry pid)
    persistent = nil,    -- the persistent-session child (lazy, first accept)
    spawning = nil,      -- queued ensure_persistent callbacks while spawning
    session = { id = nil, file = nil, n = 0 },
    pending = {},        -- id -> pending edit
    next_pending = 0,
    seq = 0,
    ns = nil,
}

-- child = { job, pid, role = "oneshot"|"persistent", tail, pending = {},
--           streaming, settled, instruction, bufs = { bufnr -> { pre, post } },
--           pendings = { pending ids } }

-- ---------------------------------------------------------------- logging --

local DEBUG = vim.env.PI_NVIM_DEBUG ~= nil

local function log(...)
    if not DEBUG then return end
    local f = io.open(("/tmp/pi-nvim-%d.log"):format(vim.fn.getpid()), "a")
    if f then
        f:write(os.date("%H:%M:%S "), table.concat(vim.tbl_map(tostring, { ... }), " "), "\n")
        f:close()
    end
end

-- ------------------------------------------------------------- rpc plumbing --

local function rpc_send(child, obj)
    if not child or not child.job then return false end
    vim.fn.chansend(child.job, vim.json.encode(obj) .. "\n")
    return true
end

---Send an RPC command to a specific child; cb(data, err) fires on the response.
local function rpc_request(child, type_, fields, cb, timeout_ms)
    if not child or not child.job then
        if cb then cb(nil, "child not running") end
        return
    end
    S.seq = S.seq + 1
    local id = tostring(S.seq)
    local req = vim.tbl_extend("force", { id = id, type = type_ }, fields or {})
    local timer
    if cb then
        timer = vim.fn.timer_start(timeout_ms or 10000, function()
            local p = child.pending[id]
            if p then
                child.pending[id] = nil
                p.cb(nil, "timeout")
            end
        end)
    end
    child.pending[id] = { cb = cb, timer = timer }
    rpc_send(child, req)
end

local function resolve_pending(child, msg)
    local p = child.pending[msg.id]
    if not p then return end
    child.pending[msg.id] = nil
    if p.timer then vim.fn.timer_stop(p.timer) end
    if not p.cb then return end
    if msg.success == false then
        p.cb(nil, msg.error or "command failed")
    else
        p.cb(msg.data, nil)
    end
end

local function dispatch(msg, child)
    local t = msg.type
    if t == "response" then
        resolve_pending(child, msg)
    elseif t == "agent_start" then
        child.streaming = true
    elseif t == "agent_settled" then
        child.streaming = false
        child.settled = true
        if child.role == "oneshot" then M._oneshot_settled(child) end
    elseif t == "extension_ui_request" then
        M._bridge_ui(msg, child)
    elseif t == "extension_error" then
        vim.notify(("π extension error (%s): %s"):format(msg.extensionPath or "?", msg.error or "?"),
            vim.log.levels.ERROR)
    end
end

local function feed(child, data)
    if not data or #data == 0 then return end
    for i = 1, #data do
        local line = data[i]
        if i < #data then
            local full = child.tail .. line
            child.tail = ""
            local ok, msg = pcall(vim.json.decode, full)
            if ok then
                log("<<", full)
                dispatch(msg, child)
            end
        elseif line ~= "" then
            child.tail = child.tail .. line
        end
    end
end

-- ------------------------------------------------------------ child control --

local function kill_child(child)
    if not child then return end
    if child == S.persistent then S.persistent = nil end
    if child.job then
        local j = child.job
        child.job = nil
        vim.fn.jobstop(j)
    end
end

---Read the ZAI key once per nvim process (children re-export it so the
---wrapper skips `pass`; first read may touch the gpg agent).
local function cache_zai_key()
    if S.zai_key then return end
    local out = vim.fn.systemlist({ "pass", "zai_pi_api_key" })
    if vim.v.shell_error == 0 and out and out[1] and out[1] ~= "" then
        S.zai_key = out[1]
    end
end

local function spawn_child(role, extra_args)
    if vim.fn.executable(pi_bin) ~= 1 then
        vim.notify("π: `pi` not on $PATH", vim.log.levels.ERROR)
        return nil
    end
    cache_zai_key()
    local args = { pi_bin, "--mode", "rpc" }
    vim.list_extend(args, extra_args or {})
    local child = {
        role = role, job = nil, pid = nil, tail = "",
        pending = {}, streaming = false, settled = false,
        instruction = nil, bufs = {}, pendings = {},
    }
    local env = vim.tbl_extend("force", vim.fn.environ(), { PI_NVIM_SOCKET = S.socket_path })
    if S.zai_key then env.ZAI_API_KEY = S.zai_key end
    child.job = vim.fn.jobstart(args, {
        cwd = vim.fn.getcwd(),
        env = env,
        on_stdout = function(j, data, _)
            local c = S.children[j]
            if c then feed(c, data) end
        end,
        on_stderr = function(_, data)
            if data and #data > 0 then log("stderr:", table.concat(data, "\n")) end
        end,
        on_exit = function(j, code, _)
            local c = S.children[j]
            if not c then return end
            S.children[j] = nil
            if c.pid then S.by_pid[c.pid] = nil end
            c.job = nil
            if c == S.persistent then S.persistent = nil end
            if code ~= 0 then
                vim.notify(("π: %s child exited (%d) — see /tmp/pi-nvim-%d.log")
                    :format(c.role, code, vim.fn.getpid()), vim.log.levels.WARN)
            end
        end,
    })
    if child.job <= 0 then
        vim.notify("π: failed to spawn pi --mode rpc", vim.log.levels.ERROR)
        return nil
    end
    child.pid = vim.fn.jobpid(child.job)
    S.children[child.job] = child
    S.by_pid[child.pid] = child
    return child
end

-- ---------------------------------------------------------- edit applying --

local function find_buffer(abspath)
    local target = vim.fn.resolve(abspath)
    for _, b in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(b) then
            local name = api.nvim_buf_get_name(b)
            if name ~= "" and vim.fn.resolve(name) == target then return b end
        end
    end
    return nil
end

---Replace oldText with newText in the buffer, mirroring pi's edit semantics:
---exact plain match, must occur exactly once.
local function apply_edit(buf, old_text, new_text)
    if type(old_text) ~= "string" or type(new_text) ~= "string" then
        return "edit: oldText/newText must be strings"
    end
    if old_text == "" then return "edit: oldText is empty" end
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    local s, e = text:find(old_text, 1, true)
    if not s then return ("edit: oldText not found in %s"):format(api.nvim_buf_get_name(buf)) end
    if text:find(old_text, e + 1, true) then
        return ("edit: oldText occurs more than once in %s; make it unique"):format(api.nvim_buf_get_name(buf))
    end
    local replaced = text:sub(1, s - 1) .. new_text .. text:sub(e + 1)
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(replaced, "\n", { plain = true }))
    return nil
end

local function apply_write(buf, content)
    if type(content) ~= "string" then return "write: content must be a string" end
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
    return nil
end

local function write_buffer(buf)
    pcall(api.nvim_buf_call, buf, function() vim.cmd("silent! write") end)
    if vim.bo[buf].modified then
        return ("write failed for %s (readonly?)"):format(api.nvim_buf_get_name(buf))
    end
    return nil
end

---Handle one request from the nvim-edit extension. Returns the reply table.
local function handle_op(req)
    local reply = { id = req.id, applied = false }
    if req.op ~= "edit" and req.op ~= "write" then
        reply.error = ("unknown op %s"):format(tostring(req.op))
        return reply
    end
    local ok, err = pcall(function()
        local buf = find_buffer(req.path)
        if not buf then
            reply.reason = "no-buffer"
            return
        end
        local aerr
        if req.op == "edit" then
            aerr = apply_edit(buf, req.oldText, req.newText)
        else
            aerr = apply_write(buf, req.content)
        end
        if aerr then reply.error = aerr; return end
        aerr = write_buffer(buf)
        if aerr then reply.error = aerr; return end
        reply.applied = true
        -- Attribute the edit to its one-shot child and snapshot the post
        -- state — the pre snapshot was taken at prompt submit.
        local child = req.pid and S.by_pid[req.pid] or nil
        if child and child.role == "oneshot" then
            local st = child.bufs[buf]
            if st then st.post = api.nvim_buf_get_lines(buf, 0, -1, false) end
        end
    end)
    if not ok then reply.error = tostring(err) end
    return reply
end

-- --------------------------------------------------------- socket server --

local function start_server()
    if S.server then return end
    S.socket_path = ("/tmp/pi-nvim-%d.sock"):format(vim.fn.getpid())
    pcall(uv.fs_unlink, S.socket_path)
    local server = uv.new_pipe(false)
    local ok, err = pcall(server.bind, server, S.socket_path)
    if not ok then
        server:close()
        vim.notify(("π: cannot bind %s: %s"):format(S.socket_path, tostring(err)), vim.log.levels.ERROR)
        return
    end
    -- 448 = 0o600. Without this the socket is world-accessible: any local
    -- process could connect and drive buffer edits/writes.
    pcall(uv.fs_chmod, S.socket_path, 448)
    server:listen(128, function(lerr)
        if lerr then return end
        local client = uv.new_pipe(false)
        pcall(server.accept, server, client)
        local buf = ""
        client:read_start(function(rerr, chunk)
            if rerr or chunk == nil then
                pcall(client.close, client)
                return
            end
            buf = buf .. chunk
            while true do
                local nl = buf:find("\n", 1, true)
                if not nl then break end
                local line = buf:sub(1, nl - 1)
                buf = buf:sub(nl + 1)
                local okd, req = pcall(vim.json.decode, line)
                if okd and type(req) == "table" and req.id then
                    log("sock<<", line)
                    vim.schedule(function()
                        local reply = handle_op(req)
                        client:write(vim.json.encode(reply) .. "\n", function()
                            pcall(client.close, client)
                        end)
                    end)
                end
            end
        end)
    end)
    S.server = server
end

local function stop_server()
    if S.server then
        pcall(S.server.close, S.server)
        S.server = nil
    end
    if S.socket_path then
        pcall(uv.fs_unlink, S.socket_path)
    end
end

-- -------------------------------------------------------- pending edits --

---Parse unified diff hunk headers; returns { { a = new_start, len = count } }.
local function diff_hunks(diff)
    local hunks = {}
    for _, line in ipairs(vim.split(diff, "\n", { plain = true })) do
        local a, b = line:match("^@@%s*%-%d+,?%d*%s+%+(%d+),?(%d*)")
        if a then table.insert(hunks, { a = tonumber(a), len = tonumber(b) or 1 }) end
    end
    return hunks
end

local function count_pending()
    local n = 0
    for _ in pairs(S.pending) do n = n + 1 end
    return n
end

local function clear_pending(p)
    for _, m in ipairs(p.marks) do
        pcall(api.nvim_buf_del_extmark, p.buf, S.ns, m)
    end
    p.marks = {}
    S.pending[p.id] = nil
    local c = p.child
    if c then
        for i, id in ipairs(c.pendings or {}) do
            if id == p.id then table.remove(c.pendings, i) break end
        end
        if c.role == "oneshot" and #c.pendings == 0 then kill_child(c) end
    end
end

---Create a pending edit from a child's pre→post diff and highlight its hunks.
local function create_pending(child, buf, diff)
    S.next_pending = S.next_pending + 1
    local p = {
        id = S.next_pending, buf = buf, child = child,
        instruction = child.instruction,
        pre = child.bufs[buf].pre, post = child.bufs[buf].post,
        diff = diff, marks = {}, a = nil, b = nil,
    }
    local line_count = api.nvim_buf_line_count(buf)
    for _, h in ipairs(diff_hunks(diff)) do
        if p.a == nil or h.a < p.a then p.a = h.a end
        if h.len > 0 and (p.b == nil or h.a + h.len - 1 > p.b) then p.b = h.a + h.len - 1 end
        local start = math.max(h.a - 1, 0)
        local endrow = math.min(start + math.max(h.len - 1, 0), line_count - 1)
        local ok, m = pcall(api.nvim_buf_set_extmark, buf, S.ns, start, 0, {
            end_line = endrow, end_col = 0, hl_group = "PiPendingEdit", strict = false,
        })
        if ok then table.insert(p.marks, m) end
    end
    S.pending[p.id] = p
    table.insert(child.pendings, p.id)
    return p
end

---Apply (or reverse) a unified diff to `lines` via unix patch --merge.
---Returns new_lines, nil | nil, error. Conflicts land as <<< >>> markers.
local function run_patch(lines, diff, reverse)
    if vim.fn.executable("patch") ~= 1 then return nil, "patch not on $PATH" end
    local base = vim.fn.tempname()
    local cur_f, patch_f, out_f = base .. ".cur", base .. ".patch", base .. ".out"
    local f = io.open(cur_f, "w")
    if not f then return nil, "cannot write temp file" end
    f:write(#lines > 0 and (table.concat(lines, "\n") .. "\n") or "\n")
    f:close()
    f = io.open(patch_f, "w")
    if not f then
        os.remove(cur_f)
        return nil, "cannot write temp file"
    end
    f:write(diff .. "\n")
    f:close()
    local args = { "patch", "--merge", "-f", "-r", "-", "-o", out_f }
    if reverse then table.insert(args, "-R") end
    vim.list_extend(args, { cur_f, "-i", patch_f })
    vim.fn.system(args)
    local code = vim.v.shell_error
    local out
    if code <= 1 and vim.fn.filereadable(out_f) == 1 then
        out = vim.fn.readfile(out_f)
    end
    os.remove(cur_f)
    os.remove(patch_f)
    os.remove(out_f)
    if not out then return nil, ("patch exited %d"):format(code) end
    return out, nil
end

local function write_buf(buf)
    pcall(api.nvim_buf_call, buf, function() vim.cmd("silent update") end)
end

local function persist_accept(p)
    M._ensure_persistent(function(child)
        if not child then
            vim.notify("π: could not start persistent session — edit not recorded", vim.log.levels.WARN)
            return
        end
        local payload = vim.json.encode({
            file = api.nvim_buf_get_name(p.buf),
            a = p.a, b = p.b,
            instruction = p.instruction,
            diff = p.diff,
        })
        -- Extension command: appends the nvim.acceptedEdit block, no agent turn.
        rpc_request(child, "prompt", { message = "/nvim-accept " .. payload }, function(_, err)
            if err then vim.notify("π: persist failed — " .. err, vim.log.levels.WARN) end
        end)
    end)
end

local function accept_pending(p)
    local cur = api.nvim_buf_get_lines(p.buf, 0, -1, false)
    if not vim.deep_equal(cur, p.post) then
        local new, err = run_patch(cur, p.diff, false)
        if not new then
            vim.notify("π: accept failed — " .. tostring(err), vim.log.levels.ERROR)
            return
        end
        api.nvim_buf_set_lines(p.buf, 0, -1, false, new)
    end
    clear_pending(p)
    write_buf(p.buf)
    persist_accept(p)
    vim.notify(("π: accepted (%d pending)"):format(count_pending()), vim.log.levels.INFO)
end

local function reject_pending(p)
    local cur = api.nvim_buf_get_lines(p.buf, 0, -1, false)
    if vim.deep_equal(cur, p.post) then
        api.nvim_buf_set_lines(p.buf, 0, -1, false, p.pre) -- exact revert
    else
        local new, err = run_patch(cur, p.diff, true)
        if not new then
            vim.notify("π: reject failed — " .. tostring(err), vim.log.levels.ERROR)
            return
        end
        api.nvim_buf_set_lines(p.buf, 0, -1, false, new)
    end
    clear_pending(p)
    write_buf(p.buf)
    vim.notify(("π: rejected (%d pending)"):format(count_pending()), vim.log.levels.INFO)
end

---Pending edit whose highlighted hunk contains the cursor, if any.
local function pending_under_cursor()
    local buf = api.nvim_get_current_buf()
    local row = vim.fn.line(".") - 1
    for _, p in pairs(S.pending) do
        if p.buf == buf then
            for _, m in ipairs(p.marks) do
                local ok, sp = pcall(api.nvim_buf_get_extmark_by_id, buf, S.ns, m, { details = true })
                if ok and sp and type(sp[1]) == "number" then
                    local endrow = type(sp.end_row) == "number" and sp.end_row or sp[1]
                    if row >= sp[1] and row <= endrow then return p end
                end
            end
        end
    end
    return nil
end

local function sorted_pending_ids()
    local ids = {}
    for id in pairs(S.pending) do table.insert(ids, id) end
    table.sort(ids)
    return ids
end

---Jump to a pending edit's first hunk (switching buffers if needed).
local function jump_to(p)
    if not p or api.nvim_get_current_buf() ~= p.buf then
        if p and api.nvim_buf_is_valid(p.buf) then
            api.nvim_set_current_buf(p.buf)
        else
            return false
        end
    end
    for _, m in ipairs(p.marks) do
        local ok, sp = pcall(api.nvim_buf_get_extmark_by_id, p.buf, S.ns, m, { details = true })
        if ok and sp and type(sp[1]) == "number" then
            pcall(api.nvim_win_set_cursor, 0, { sp[1] + 1, 0 })
            return true
        end
    end
    return false
end

local function cycle_pending(dir)
    local ids = sorted_pending_ids()
    if #ids == 0 then
        vim.notify("π: no pending edits", vim.log.levels.INFO)
        return
    end
    local cur = pending_under_cursor()
    local pos = 0
    if cur then
        for i, id in ipairs(ids) do
            if id == cur.id then pos = i break end
        end
    end
    local idx = ((pos + dir - 1) % #ids) + 1
    local p = S.pending[ids[idx]]
    jump_to(p)
    vim.notify(("π pending %d/%d: %s"):format(idx, #ids, (p.instruction or ""):sub(1, 80)),
        vim.log.levels.INFO)
end

---agent_settled for a one-shot: build pending edits from pre→post snapshots.
local function joined(lines)
    if #lines == 0 then return "\n" end
    return table.concat(lines, "\n") .. "\n"
end

function M._oneshot_settled(child)
    local last
    for buf, st in pairs(child.bufs) do
        if st.post then
            local diff = vim.text.diff(joined(st.pre), joined(st.post), { ctxlen = 3 })
            if diff ~= "" then last = create_pending(child, buf, diff) end
        end
    end
    if not last then
        rpc_request(child, "get_last_assistant_text", {}, function(data)
            local txt = type(data) == "table" and type(data.text) == "string" and data.text or nil
            local extra = (txt and txt ~= "") and (" — " .. txt:sub(1, 200)) or ""
            vim.notify("π: no edit produced" .. extra, vim.log.levels.WARN)
            kill_child(child)
        end)
        return
    end
    jump_to(last)
    vim.notify(("π edit ready — <leader>gp accept · <leader>gr reject · <leader>g] next (%d pending)")
        :format(count_pending()), vim.log.levels.INFO)
end

-- ---------------------------------------------------- persistent session --

function M._ensure_persistent(cb)
    start_server()
    if S.persistent and S.persistent.job then
        cb(S.persistent)
        return
    end
    if S.spawning then
        table.insert(S.spawning, cb)
        return
    end
    S.spawning = { cb }
    local function flush(child)
        local cbs = S.spawning
        S.spawning = nil
        for _, c in ipairs(cbs or {}) do c(child) end
    end
    if not S.session.id then S.session.id = ("nvim-%d"):format(vim.fn.getpid()) end
    local extra
    if S.session.file and vim.fn.filereadable(S.session.file) == 1 then
        extra = { "--session", S.session.file }
    else
        extra = { "--session-id", S.session.id }
    end
    local child = spawn_child("persistent", extra)
    if not child then
        flush(nil)
        return
    end
    S.persistent = child
    rpc_request(child, "get_state", {}, function(data, err)
        if data and data.sessionFile then
            S.session.file = data.sessionFile
            log("session:", tostring(data.sessionFile))
        else
            log("get_state failed:", tostring(err))
        end
        flush(child)
    end, 15000)
end

local function new_session()
    if S.persistent then kill_child(S.persistent) end
    S.session.file = nil
    S.session.n = S.session.n + 1
    S.session.id = ("nvim-%d-%d"):format(vim.fn.getpid(), S.session.n)
    vim.notify("π: next prompt/edit starts session " .. S.session.id, vim.log.levels.INFO)
end

-- ----------------------------------------------------------- prompt float --

local function close_float()
    if S.float_win and api.nvim_win_is_valid(S.float_win) then
        api.nvim_win_close(S.float_win, true)
    end
    S.float_win = nil
    S.float_buf = nil
    S.ctx = nil
end

local function rel_path(path)
    local cwd = vim.fn.getcwd()
    local r = (path:sub(1, #cwd) == cwd) and vim.fn.fnamemodify(path, ":.") or path
    if r:find("%s") then return path end -- @tokens must be whitespace-free
    return r
end

local function capture_context()
    local buf = api.nvim_get_current_buf()
    local path = api.nvim_buf_get_name(buf)
    local ctx = { buf = buf, filetype = vim.bo[buf].filetype, path = path }
    local mode = api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then
        local s = vim.fn.getpos("v")[2]
        local e = vim.fn.line(".")
        if s > e then s, e = e, s end
        ctx.sline, ctx.eline = s, e
        ctx.lines = api.nvim_buf_get_lines(buf, s - 1, e, false)
    end
    return ctx
end

local function winbar_text(ctx)
    if not ctx.path or ctx.path == "" then return " π (scratch)" end
    local name = vim.fn.fnamemodify(ctx.path, ":t")
    if ctx.lines then
        return (" π %s:L%d-%d"):format(name, ctx.sline, ctx.eline)
    end
    return (" π %s"):format(name)
end

---@ref for prompt_expansion (file arrives pre-read), numbered selection,
---then the instruction.
local function build_message(ctx, text)
    local parts = {}
    local rel = rel_path(ctx.path)
    table.insert(parts, "@" .. rel)
    if ctx.lines then
        table.insert(parts, "")
        table.insert(parts, ("[selection: %s, lines %d-%d]"):format(rel, ctx.sline, ctx.eline))
        for i, l in ipairs(ctx.lines) do
            table.insert(parts, ("%d| %s"):format(ctx.sline + i - 1, l))
        end
    end
    table.insert(parts, "")
    table.insert(parts, "User instructions:")
    table.insert(parts, text)
    return table.concat(parts, "\n")
end

local function submit()
    local buf = S.float_buf
    if not buf or not api.nvim_buf_is_valid(buf) then return close_float() end
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, "\n"))
    local ctx = S.ctx
    close_float()
    if text == "" then return end
    if not ctx or not ctx.buf or not api.nvim_buf_is_valid(ctx.buf) or ctx.path == "" then
        vim.notify("π: need a named file buffer", vim.log.levels.ERROR)
        return
    end
    start_server()
    write_buf(ctx.buf) -- prompt_expansion reads from disk
    local child = spawn_child("oneshot", {
        "--no-session", "--model", oneshot_model,
        "--append-system-prompt", ONESHOT_DIRECTIVE,
    })
    if not child then return end
    child.instruction = text
    child.bufs[ctx.buf] = { pre = api.nvim_buf_get_lines(ctx.buf, 0, -1, false), post = nil }
    local msg = build_message(ctx, text)
    rpc_request(child, "prompt", { message = msg }, function(_, err)
        if err then vim.notify("π: " .. err, vim.log.levels.ERROR) end
    end)
    vim.notify("π: oneshot running… (<leader>gk abort)", vim.log.levels.INFO)
end

local function open_prompt()
    S.ctx = capture_context()
    close_float()
    local w = math.max(40, math.floor(vim.o.columns * 0.6))
    local h = math.max(5, math.floor(vim.o.lines * 0.35))
    local row = math.max(1, math.floor((vim.o.lines - h) / 2) - 2)
    local col = math.floor((vim.o.columns - w) / 2)
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    local win = api.nvim_open_win(buf, true, {
        relative = "editor", width = w, height = h, row = row, col = col,
        border = "rounded", style = "minimal", title = " π ", title_pos = "center",
    })
    vim.wo[win].wrap = true
    vim.wo[win].winbar = winbar_text(S.ctx)
    S.float_win, S.float_buf = win, buf
    vim.keymap.set({ "n", "i" }, "<CR>", submit, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", close_float, { buffer = buf, silent = true })
    vim.cmd("startinsert")
end

-- ----------------------------------------------------------------- detach --

local function tui_command()
    if S.session.file and vim.fn.filereadable(S.session.file) == 1 then
        return ("%s --session %s"):format(pi_bin, vim.fn.shellescape(S.session.file))
    end
    return ("%s --session-id %s"):format(pi_bin, S.session.id or ("nvim-%d"):format(vim.fn.getpid()))
end

local function detach_tui()
    local function go()
        local cmd = tui_command()
        for _, c in pairs(vim.tbl_values(S.children)) do kill_child(c) end
        if vim.env.TMUX then
            vim.fn.system({ "tmux", "split-window", "-h", "-c", vim.fn.getcwd(), cmd })
            vim.notify("π: session opened in tmux split")
        else
            vim.cmd("!" .. cmd)
        end
    end
    if S.persistent and S.persistent.job then
        rpc_request(S.persistent, "get_state", {}, function(data)
            if data and data.sessionFile then S.session.file = data.sessionFile end
            go()
        end, 1500)
    else
        go()
    end
end

-- ----------------------------------------------------- extension ui bridge --

-- Extension dialogs over RPC -> vim.ui (async — a blocking dialog would starve
-- the edit socket). Requests the agent already timed out on are answered
-- harmlessly (pcall-guarded send).
function M._bridge_ui(req, child)
    local method = req.method
    local function respond(payload)
        local body = vim.tbl_extend("force", { type = "extension_ui_response", id = req.id }, payload)
        pcall(rpc_send, child, body)
    end
    if method == "select" then
        vim.ui.select(req.options or {}, { prompt = req.title or "π" }, function(choice)
            if choice == nil then respond({ cancelled = true }) else respond({ value = choice }) end
        end)
    elseif method == "confirm" then
        local body = (req.message or ""):gsub("\n", " ")
        local prompt = body ~= "" and ((req.title or "π") .. " — " .. body) or (req.title or "π")
        vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
            if choice == nil then respond({ cancelled = true }) else respond({ confirmed = choice == "Yes" }) end
        end)
    elseif method == "input" or method == "editor" then
        vim.ui.input({ prompt = (req.title or "π") .. ": ", default = req.placeholder or req.prefill or "" },
            function(val)
                if val == nil then respond({ cancelled = true }) else respond({ value = val }) end
            end)
    elseif method == "notify" then
        local lvl = (req.notifyType == "error" and vim.log.levels.ERROR)
            or (req.notifyType == "warning" and vim.log.levels.WARN)
            or vim.log.levels.INFO
        vim.notify("π: " .. (req.message or ""), lvl)
    end
    -- setStatus / setWidget / setTitle / set_editor_text: fire-and-forget.
end

-- ----------------------------------------------------------------- abort --

local function abort()
    local any = false
    for _, c in pairs(S.children) do
        if c.streaming then
            rpc_request(c, "abort", {}, nil, 3000)
            any = true
        end
    end
    vim.notify(any and "π: aborted" or "π: nothing streaming")
end

local function stop_all()
    for _, c in pairs(vim.tbl_values(S.children)) do kill_child(c) end
end

-- ----------------------------------------------------------------- setup --

local function leader_gp()
    local mode = api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then return open_prompt() end
    local p = pending_under_cursor()
    if p then
        accept_pending(p)
    else
        open_prompt()
    end
end

local function setup()
    S.ns = api.nvim_create_namespace("user-pi-pending")
    api.nvim_set_hl(0, "PiPendingEdit", { default = true, link = "DiffChange" })

    local group = api.nvim_create_augroup("user-pi", { clear = true })

    api.nvim_create_user_command("PiState", function()
        local lines = {
            ("socket: %s"):format(tostring(S.socket_path)),
            ("session id: %s"):format(tostring(S.session.id)),
            ("session file: %s"):format(tostring(S.session.file)),
            ("children: %d (%s)"):format(vim.tbl_count(S.children),
                table.concat(vim.tbl_map(function(c) return c.role end,
                    vim.tbl_values(S.children)), ", ")),
            ("pending: %d"):format(count_pending()),
        }
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, {})
    api.nvim_create_user_command("PiEdits", function()
        local ids = sorted_pending_ids()
        if #ids == 0 then return vim.notify("π: no pending edits", vim.log.levels.INFO) end
        local out = {}
        for i, id in ipairs(ids) do
            local p = S.pending[id]
            table.insert(out, ("%d. %s:%s-%s — %s"):format(i,
                vim.fn.fnamemodify(api.nvim_buf_get_name(p.buf), ":t"),
                tostring(p.a), tostring(p.b), (p.instruction or ""):sub(1, 60)))
        end
        vim.notify(table.concat(out, "\n"), vim.log.levels.INFO)
    end, {})
    api.nvim_create_user_command("PiNew", new_session, {})
    api.nvim_create_user_command("PiPromptRaw", function(opts)
        if opts.args == "" then return end
        M._ensure_persistent(function(child)
            if not child then return vim.notify("π: no session", vim.log.levels.ERROR) end
            rpc_request(child, "prompt", { message = opts.args }, function(_, err)
                if err then vim.notify("π: " .. err, vim.log.levels.ERROR) end
            end)
        end)
    end, { nargs = 1 })
    api.nvim_create_user_command("PiStop", stop_all, {})
    api.nvim_create_user_command("PiAbort", abort, {})

    vim.keymap.set({ "n", "v" }, "<leader>gp", leader_gp, { desc = "π prompt / accept edit" })
    vim.keymap.set("n", "<leader>gr", function()
        local p = pending_under_cursor()
        if p then reject_pending(p) else vim.notify("π: no pending edit under cursor", vim.log.levels.INFO) end
    end, { desc = "π reject edit" })
    vim.keymap.set("n", "<leader>g]", function() cycle_pending(1) end, { desc = "π next pending edit" })
    vim.keymap.set("n", "<leader>g[", function() cycle_pending(-1) end, { desc = "π prev pending edit" })
    vim.keymap.set("n", "<leader>gP", detach_tui, { desc = "π open TUI session" })
    vim.keymap.set("n", "<leader>gk", abort, { desc = "π abort" })

    api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(args)
            for _, p in pairs(vim.tbl_values(S.pending)) do
                if p.buf == args.buf then clear_pending(p) end
            end
        end,
    })
    api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            stop_all()
            stop_server()
        end,
    })
end

-- Exposed for tests.
M._S = S
M._handle_op = handle_op
M._start_server = start_server
M._spawn_child = spawn_child
M._feed = feed
M._diff_hunks = diff_hunks
M._run_patch = run_patch

setup()
return M
