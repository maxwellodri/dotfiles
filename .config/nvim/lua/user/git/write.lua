-- Shared "a save during review persists the edit into git" primitive.
-- GitSplit (dirty tree) stages the file's written DELTA into the index;
-- WorktreeReview (a picked commit) records the edit as a "WIP: human edits"
-- commit on the worktree branch on write — squashed into its base commit
-- only when that commit is picked onto upstream. Same rule, different git
-- level: what was approved on screen is what git records — and nothing else.
local M = {}

local baselines = {} -- buf -> file bytes whose delta is already staged

local function read_file(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  return data
end

local function write_file(path, data)
  local f = assert(io.open(path, 'wb'))
  f:write(data)
  f:close()
end

-- Stage only the baseline→current delta, 3-way merged into the index, so
-- unrelated unstaged hunks in the same file stay unstaged. The baseline blob
-- is hashed into the ODB to give `apply --3way` its merge base. A write that
-- overlaps an unstaged hunk conflicts: nothing is staged and the index entry
-- is restored untouched (the caller reports it).
function M.stage_delta(root, path, baseline, current)
  local rel = vim.fs.relpath(root, path)
  if not rel then return false, 'path is outside the repository' end

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.dirname(tmp .. '/a/' .. rel), 'p')
  vim.fn.mkdir(vim.fs.dirname(tmp .. '/b/' .. rel), 'p')
  write_file(tmp .. '/a/' .. rel, baseline)
  write_file(tmp .. '/b/' .. rel, current)

  local res = vim.system({ 'git', '-C', root, 'hash-object', '-w', '--stdin' },
    { stdin = baseline }):wait()
  if res.code ~= 0 then return false, res.stderr or 'hash-object failed' end

  local diff = vim.system({ 'git', '-C', tmp, 'diff', '--no-index', '--src-prefix=',
    '--dst-prefix=', '--', 'a/' .. rel, 'b/' .. rel }):wait()
  if diff.code == 0 then return true end -- unchanged write, nothing to stage
  if diff.code > 1 then return false, diff.stderr or 'diff failed' end

  local patchfile = tmp .. '/delta.patch'
  write_file(patchfile, diff.stdout)

  -- snapshot the index entry: a conflicting --cached --3way leaves stages
  -- 1-3 behind and the file in UU state
  local entry = vim.system({ 'git', '-C', root, 'ls-files', '-s', '--', rel }):wait()
  local applied = vim.system({ 'git', '-C', root, 'apply', '--cached', '--3way',
    '--whitespace=nowarn', patchfile }):wait()
  if applied.code ~= 0 then
    if entry.code == 0 and entry.stdout ~= '' then
      vim.system({ 'git', '-C', root, 'update-index', '--index-info' },
        { stdin = entry.stdout }):wait()
    end
    return false, (applied.stderr ~= '' and applied.stderr or applied.stdout)
  end
  return true
end

-- Real-file buffer: after the write hits disk, stage the delta since the
-- last staged write (baseline starts at the worktree content when the
-- session picked the file up). Untracked files are the caller's call —
-- staging one is a deliberate act, there is no "delta" into an absent index
-- entry.
function M.stage_on_write(augroup, root, buf)
  baselines[buf] = read_file(vim.api.nvim_buf_get_name(buf))
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup, buffer = buf,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      local baseline, current = baselines[args.buf], read_file(path)
      if baseline == nil or current == nil then return end
      local ok, err = M.stage_delta(root, path, baseline, current)
      if ok then
        baselines[args.buf] = current
      else
        vim.notify('staged nothing for ' .. path .. ':\n' .. err
          .. '\n(the write overlapped unstaged hunks — `git add` to sweep the whole file)',
          vim.log.levels.WARN)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup, buffer = buf,
    callback = function() baselines[buf] = nil end,
  })
end

-- Virtual buffer (no backing file): :w never touches disk. `capture`
-- records the nit on the buffer (while `modified` is still readable, so it
-- can ignore unchanged writes), `apply` persists the batch. One apply per
-- write burst: `:wa` fires BufWriteCmd for every session buffer before any
-- scheduled callback runs, and the shared `session.pending_write` flag
-- coalesces them into a single pass.
function M.on_write(augroup, buf, session, capture, apply)
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = augroup, buffer = buf,
    callback = function(args)
      capture(args.buf)
      vim.bo[args.buf].modified = false
      if session.pending_write then return end
      session.pending_write = true
      vim.schedule(function()
        session.pending_write = false
        apply()
      end)
    end,
  })
end

return M
