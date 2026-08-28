-- :MergeSave — 3-way merge unsaved buffer changes with changes made on disk
-- by another process (a coding agent, formatter, coworker, ...).

local M = {}

local function notify(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO)
end

local function read_file_lines(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local lines = {}
    for line in f:lines("*L") do
        lines[#lines + 1] = line:gsub("[\r\n]+$", "")
    end
    f:close()
    return lines
end

local function write_file_lines(lines, path)
    local f = io.open(path, "w")
    if not f then
        return false
    end
    for _, line in ipairs(lines) do
        f:write(line, "\n")
    end
    f:close()
    return true
end

local function lines_equal(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function buf_lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

-- Write the current buffer to disk without vim's changed-file check (a plain
-- :w would trigger the "changed since reading it" prompt), then mark the
-- buffer clean and re-sync it (mtime bookkeeping) so later saves are normal.
local function commit_buffer_to_disk(buf, path)
    vim.cmd("noautocmd silent w !cat > " .. vim.fn.shellescape(path))
    if vim.v.shell_error ~= 0 then
        return false
    end
    vim.bo[buf].modified = false
    vim.cmd("silent checktime")
    return true
end

-- Recover the buffer's last sync point with the file: the newest undo state
-- on the current branch that was saved to file (:w marker), or the
-- undo-tree root (the file as loaded) if there is none. Both buffer and disk
-- descend from it, so it is a valid diff3 ancestor. Returns (lines, seq), or
-- nil if there is no undo history.
--
-- This temporarily rewinds the live buffer through undo history and then
-- restores the exact working state (verified; the undo tree is not damaged).
local function get_last_write_state(buf)
    local ut = vim.fn.undotree()
    if ut.seq_cur == 0 then
        return nil -- no undo history to walk back through
    end
    local working = buf_lines(buf)
    local seq = ut.seq_cur

    -- Seqs of undo states that were written to file.
    local saves = {}
    local function collect(entries)
        for _, e in ipairs(entries) do
            if e.save and e.save > 0 then
                saves[e.seq] = true
            end
            if e.entries then
                collect(e.entries)
            end
        end
    end
    collect(ut.entries)

    -- Walk the current branch backwards one undo state at a time; stop at
    -- the newest saved state, or continue to the root (file as loaded).
    local base, base_seq
    local prev = seq
    for _ = 1, 10000 do
        pcall(vim.cmd, "silent undo")
        local s = vim.fn.undotree().seq_cur
        if s == prev then
            break -- reached the undo-tree root
        end
        prev = s
        if saves[s] then
            base, base_seq = buf_lines(buf), s
            break
        end
    end
    if not base then
        base, base_seq = buf_lines(buf), 0 -- the walk left us at the root
    end

    pcall(vim.cmd, "silent undo " .. seq)
    if not lines_equal(working, buf_lines(buf)) then
        -- Safety net: exact-state restore failed, put the lines back directly.
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, working)
    end
    return base, base_seq
end

function M.merge_save()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= "" then
        return notify("MergeSave: only works on normal file buffers", vim.log.levels.WARN)
    end
    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" then
        return notify("MergeSave: buffer has no file name", vim.log.levels.WARN)
    end
    if vim.fn.executable("diff3") == 0 then
        return notify("MergeSave: diff3 not found (install diffutils)", vim.log.levels.ERROR)
    end

    local disk = read_file_lines(path)
    if not disk then
        return notify("MergeSave: cannot read " .. path, vim.log.levels.ERROR)
    end
    local cur = buf_lines(buf)

    -- Nothing unsaved in the buffer: at most a reload of the disk version.
    if not vim.bo[buf].modified then
        if not lines_equal(cur, disk) then
            vim.cmd("silent edit") -- unmodified buffer reloads without a prompt
        end
        vim.b[buf].mergesave_sync = { lines = buf_lines(buf), seq = vim.fn.undotree().seq_cur }
        return notify("Merge successful but unnecessary!")
    end

    local base, base_seq = get_last_write_state(buf)
    if not base then
        return notify("MergeSave: no undo history to recover the last saved state from", vim.log.levels.ERROR)
    end

    -- If this buffer was already :MergeSave-committed since its last real
    -- :w, our own snapshot is the fresher sync point (a :w !cat pipe write
    -- does not register a vim write state). Pick whichever is newer.
    local snap = vim.b[buf].mergesave_sync
    if snap and base_seq <= snap.seq then
        base = snap.lines
    end

    local view = vim.fn.winsaveview()

    -- Disk never diverged from the sync point: nothing to merge.
    if lines_equal(base, disk) then
        if not commit_buffer_to_disk(buf, path) then
            return notify("MergeSave: failed writing to disk", vim.log.levels.ERROR)
        end
        vim.b[buf].mergesave_sync = { lines = cur, seq = vim.fn.undotree().seq_cur }
        vim.fn.winrestview(view)
        return notify("Merge successful but unnecessary!")
    end

    -- 3-way merge: your buffer changes vs disk changes since the sync point.
    local tmp = vim.fn.tempname()
    local mine_f, base_f, theirs_f = tmp .. ".mine", tmp .. ".base", tmp .. ".theirs"
    write_file_lines(cur, mine_f)
    write_file_lines(base, base_f)
    write_file_lines(disk, theirs_f)
    local merged = vim.fn.systemlist({ "diff3", "-m",
        "-L", "buffer", "-L", "saved", "-L", "disk",
        mine_f, base_f, theirs_f })
    local rc = vim.v.shell_error
    os.remove(mine_f)
    os.remove(base_f)
    os.remove(theirs_f)
    if rc ~= 0 and rc ~= 1 then
        return notify("MergeSave: diff3 failed (exit " .. rc .. ")", vim.log.levels.ERROR)
    end

    -- Swap the buffer contents for the merged result (single undoable step),
    -- then commit it to disk and re-sync.
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, merged)
    if not commit_buffer_to_disk(buf, path) then
        return notify("MergeSave: failed writing merged result to disk (buffer kept the merged text)", vim.log.levels.ERROR)
    end
    vim.b[buf].mergesave_sync = { lines = buf_lines(buf), seq = vim.fn.undotree().seq_cur }
    vim.fn.winrestview(view)

    if rc == 1 then
        local marks = {}
        for i, line in ipairs(merged) do
            if line:match("^<<<<<<<") then
                marks[#marks + 1] = i
            end
        end
        local loc = ""
        if #marks > 0 then
            loc = string.format(" (markers at line%s %s)",
                #marks > 1 and "s" or "", table.concat(marks, ", "))
        end
        notify("Merge conflicts occurred" .. loc .. " — resolve, then :w", vim.log.levels.WARN)
    else
        notify("Merge successful")
    end
end

vim.api.nvim_create_user_command("MergeSave", M.merge_save, {
    nargs = 0,
    desc = "3-way merge unsaved buffer changes with on-disk changes (diff3)",
})

return M
