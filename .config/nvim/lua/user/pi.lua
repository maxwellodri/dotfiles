-- pi.lua — inline one-shot pi edits inside nvim.
--
-- <leader>gp (n/v): open the floating prompt. The whole file (plus the
-- numbered visual selection, when invoked from visual mode) and your
-- instruction go to a single fast oneshot agent; its edit lands on disk and is
-- adopted into the buffer when it settles. No accept/reject — undo with
-- `u`. While a oneshot runs, a visual-mode submission highlights its
-- selection origin (PiSelOrigin) and the statusline shows `π: <n in flight>`
-- (lualine component in lua/user/statusline.lua).
--
-- Oneshots spawn the nix-built pi binary directly (no scripts/pi wrapper):
-- --mode rpc --no-session, tools locked to edit, no extensions/skills/
-- prompt-templates/context-files, and a oneshot system directive instead of
-- APPEND_SYSTEM.md — prompt in, edit out, no back-and-forth.
--
-- If you typed in the buffer while a oneshot ran, its disk edit is merged
-- over your typing with `patch --merge`; same-line collisions surface as
-- standard conflict markers.
--
-- Commands: :PiState, :PiStop, :PiAbort.
-- Set PI_NVIM_DEBUG=1 to log RPC traffic to /tmp/pi-nvim-<pid>.log.
local api = vim.api
local M = {}

local oneshot = {
    model = "openrouter/openai/gpt-oss-120b", -- settings map it to low thinking
    env = "OPENROUTER_API_KEY",
    pass_entry = "openrouter_api_key",
}

local ONESHOT_DIRECTIVE = ([[You are making a single inline edit inside the user's editor.
The full file contents are already in the prompt below. Make exactly the edit
the user asked for with a single `edit` tool call, then stop. Do not reply
after the tool call. Never ask questions or wait for confirmation; if anything
is ambiguous, make the most reasonable interpretation and act. NEVER add comments
to the code — no explanatory comments, no doc comments, nothing. Only
preserve existing comments, and delete any obsoleted by your edit (e.g. a
TODO comment for a TODO you implement).]])

local function rel_path(path)
    local cwd = vim.fn.getcwd()
    local r = (path:sub(1, #cwd) == cwd) and vim.fn.fnamemodify(path, ":.") or path
    if r:find("%s") then return path end
    return r
end

local function append_visual_selection_to_prompt(rel, sline, lines)
    local parts = { ("[selection: %s, lines %d-%d]"):format(rel, sline, sline + #lines - 1) }
    for i, l in ipairs(lines) do
        table.insert(parts, ("%d| %s"):format(sline + i - 1, l))
    end
    return table.concat(parts, "\n")
end

---Full file contents (no read round-trip: the only tool is edit), numbered
---selection when present, then the instruction.
local function build_message(ctx, text)
    local parts = {}
    local rel = rel_path(ctx.path)
    table.insert(parts, rel)
    table.insert(parts, table.concat(api.nvim_buf_get_lines(ctx.buf, 0, -1, false), "\n"))
    if ctx.lines then
        table.insert(parts, "")
        table.insert(parts, append_visual_selection_to_prompt(rel, ctx.sline, ctx.lines))
    end
    table.insert(parts, "")
    table.insert(parts, "User instructions:")
    table.insert(parts, text)
    return table.concat(parts, "\n")
end

local S = {
    api_key = nil,   -- cached oneshot provider key
    children = {},  -- job id -> child
    seq = 0,
    ns = nil,
    float_win = nil,
    float_buf = nil,
    ctx = nil,
}

-- child = { job, pid, tail, pending = {}, streaming, settled, aborted,
--           instruction, bufs = { bufnr -> { pre } }, sel_mark }

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

---Send an RPC command to a child; cb(data, err) fires on the response.
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
        if not child.settled then -- settle exactly once, even on a duplicate event
            child.settled = true
            M._oneshot_settled(child)
        end
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

local function clear_sel_mark(child)
    local sm = child and child.sel_mark
    if not sm then return end
    child.sel_mark = nil
    pcall(api.nvim_buf_del_extmark, sm.buf, S.ns, sm.mark)
end

local function kill_child(child)
    if not child then return end
    clear_sel_mark(child)
    child.killed = true
    if child.job then
        local j = child.job
        child.job = nil
        vim.fn.jobstop(j)
    end
end

---Read the oneshot provider key once per nvim process so children skip the gpg round-trip.
local function get_api_key()
    if S.api_key == nil then
        local out = vim.fn.systemlist({ "pass", oneshot.pass_entry })
        if vim.v.shell_error == 0 and out and out[1] and out[1] ~= "" then
            S.api_key = out[1]
        end
    end
    return S.api_key
end

local function spawn_child(extra_args)
    -- nix_config clone hosts the dotfiles-env out-link (set by shell rc / install).
    local nixcfg = vim.env.NIX_CONFIG_DIR or (vim.env.SOURCE or (os.getenv("HOME") .. "/source")) .. "/nix_config"
    local bin = nixcfg .. "/dotfiles-env-result/bin/pi"
    if not bin or vim.fn.executable(bin) ~= 1 then
        vim.notify("π: dotfiles-env-result/bin/pi missing — run helper_scripts/install_flake.sh",
            vim.log.levels.ERROR)
        return nil
    end
    local args = { bin, "--mode", "rpc" }
    vim.list_extend(args, extra_args or {})
    local child = {
        job = nil, pid = nil, tail = "",
        pending = {}, streaming = false, settled = false, aborted = false,
        instruction = nil, bufs = {}, sel_mark = nil,
    }
    -- settings.json still needed (model thinking map); lazy MCP servers never
    -- spawn under the edit-only tool allowlist.
    local env = vim.tbl_extend("force", vim.fn.environ(), { PI_CODING_AGENT_DIR = vim.env.dotfiles .. "/pi" })
    env.PI_NVIM_ONESHOT = "1" -- gates oneshot-edit.ts (auto-discovered elsewhere)
    local key = get_api_key()
    if key then env[oneshot.env] = key end
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
            c.job = nil
            clear_sel_mark(c)
            -- 143 = SIGTERM from our own jobstop; only genuine crashes warn.
            if code ~= 0 and not c.killed then
                vim.notify(("π: child exited (%d) — see /tmp/pi-nvim-%d.log")
                    :format(code, vim.fn.getpid()), vim.log.levels.WARN)
            end
        end,
    })
    if child.job <= 0 then
        vim.notify("π: failed to spawn pi --mode rpc", vim.log.levels.ERROR)
        return nil
    end
    child.pid = vim.fn.jobpid(child.job)
    S.children[child.job] = child
    return child
end

-- ---------------------------------------------------------------- adopt --

local function joined(lines)
    if #lines == 0 then return "\n" end
    return table.concat(lines, "\n") .. "\n"
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
    -- the oneshot's own disk write makes `update` prompt "file changed since
    -- reading"; `!` writes through it (buffer content already matches disk)
    pcall(api.nvim_buf_call, buf, function() vim.cmd("silent update!") end)
end

---agent_settled: the native edit tool wrote disk directly — adopt it into the
---buffer (merging over any typing that happened meanwhile), then done.
function M._oneshot_settled(child)
    clear_sel_mark(child)
    local edited = false
    for buf, st in pairs(child.bufs) do
        if api.nvim_buf_is_valid(buf) then
            local name = api.nvim_buf_get_name(buf)
            local disk = (name ~= "" and vim.fn.filereadable(name) == 1) and vim.fn.readfile(name) or nil
            if disk and not vim.deep_equal(disk, st.pre) then
                local cur = api.nvim_buf_get_lines(buf, 0, -1, false)
                if vim.deep_equal(cur, st.pre) then
                    api.nvim_buf_set_lines(buf, 0, -1, false, disk)
                elseif not vim.deep_equal(cur, disk) then
                    -- autoread may have already synced the edit into the buffer;
                    -- only genuine user typing needs a merge
                    local d = vim.text.diff(joined(st.pre), joined(disk), { ctxlen = 3 })
                    local merged = run_patch(cur, d, false)
                    if merged then api.nvim_buf_set_lines(buf, 0, -1, false, merged) end
                end
                write_buf(buf)
                edited = true
            end
        end
    end
    if edited then
        kill_child(child)
        return
    end
    rpc_request(child, "get_last_assistant_text", {}, function(data)
        local txt = type(data) == "table" and type(data.text) == "string" and data.text or nil
        local extra = (txt and txt ~= "") and (" — " .. txt:sub(1, 200)) or ""
        -- No assistant text and not user-aborted: run likely failed (timeout/error).
        local lvl = ((txt and txt ~= "") or child.aborted) and vim.log.levels.INFO or vim.log.levels.WARN
        vim.notify("π: no edit produced" .. extra, lvl)
        kill_child(child)
    end)
end

-- ----------------------------------------------------------- prompt float --

local function close_float()
    if S.float_win and api.nvim_win_is_valid(S.float_win) then
        api.nvim_win_close(S.float_win, true)
    end
    vim.cmd("stopinsert")
    S.float_win = nil
    S.float_buf = nil
    S.ctx = nil
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
    if not get_api_key() then
        vim.notify(("π: no %s — check `pass %s`"):format(oneshot.env, oneshot.pass_entry), vim.log.levels.ERROR)
        return
    end
    write_buf(ctx.buf) -- the edit tool operates on disk
    local child = spawn_child({
        "--no-session", "--model", oneshot.model,
        "--append-system-prompt", ONESHOT_DIRECTIVE,
        "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files",
        "--tools", "edit",
        "--extension", vim.env.dotfiles .. "/pi/extensions/oneshot-edit.ts",
    })
    if not child then return end
    child.instruction = text
    child.bufs[ctx.buf] = { pre = api.nvim_buf_get_lines(ctx.buf, 0, -1, false) }
    if ctx.sline then
        local ok, m = pcall(api.nvim_buf_set_extmark, ctx.buf, S.ns, ctx.sline - 1, 0, {
            end_line = ctx.eline, end_col = 0, hl_group = "PiSelOrigin", strict = false,
        })
        if ok then child.sel_mark = { buf = ctx.buf, mark = m } end
    end
    rpc_request(child, "prompt", { message = build_message(ctx, text) }, function(_, err)
        if err then vim.notify("π: " .. err, vim.log.levels.ERROR) end
    end)
    vim.notify("π: oneshot running… (:PiAbort to cancel)", vim.log.levels.INFO)
end

local function open_prompt()
    close_float() -- nils S.ctx and refocuses the real buffer; must precede the capture
    S.ctx = capture_context()
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

-- ----------------------------------------------------------------- abort --

local function abort()
    local any = false
    for _, c in pairs(S.children) do
        if c.streaming then
            rpc_request(c, "abort", {}, nil, 3000)
            c.aborted = true
            any = true
        end
    end
    vim.notify(any and "π: aborted" or "π: nothing streaming")
end

local function stop_all()
    for _, c in pairs(vim.tbl_values(S.children)) do kill_child(c) end
end

-- ----------------------------------------------------------------- setup --

local function setup()
    S.ns = api.nvim_create_namespace("user-pi")
    api.nvim_set_hl(0, "PiSelOrigin", { default = true, link = "Visual" })

    local group = api.nvim_create_augroup("user-pi", { clear = true })

    api.nvim_create_user_command("PiState", function()
        local cs = vim.tbl_values(S.children)
        vim.notify(("children: %d (%d streaming)"):format(#cs,
            #vim.tbl_filter(function(c) return c.streaming end, cs)), vim.log.levels.INFO)
    end, {})
    api.nvim_create_user_command("PiStop", stop_all, {})
    api.nvim_create_user_command("PiAbort", abort, {})

    vim.keymap.set({ "n", "v" }, "<leader>gp", open_prompt, { desc = "π oneshot prompt" })

    api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = stop_all,
    })
end

function M.statusline()
    local n = 0
    for _, c in pairs(S.children) do
        if not c.settled then n = n + 1 end
    end
    return ("π: %d"):format(n)
end

-- Exposed for tests.
M._S = S
M._build_message = build_message
M._run_patch = run_patch
M._open_prompt = open_prompt
M._submit = submit
M._feed = feed

setup()
return M
