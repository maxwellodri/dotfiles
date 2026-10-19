-- WorktreeReview: review-and-upstream queue for agent worktrees.
--
--   <leader>gS  pick a worktree under <root>/worktrees/ -> pick a commit
--               (oldest un-upstreamed first) -> review tab
--
-- The review tab mirrors GitSplit: left = commit^, right = commit, one file
-- pair at a time. The right pane is an editable virtual buffer: edit it and
-- :w — the edit is squashed into the commit (patch + fixup + autosquash
-- rebase) and the rewritten commit re-opens. <leader>gcp cherry-picks the
-- commit onto the upstream branch in the main worktree — the pick only; no
-- worktree rebase, conflicts are resolved by hand. The queue tracks picks by
-- patch-id, so a picked commit drops out even before the worktree is
-- rebased onto upstream. <leader>gcp also works OUTSIDE the session (any
-- window): it picks the last reviewed commit; the pointer clears on a
-- successful pick.
--
-- The worktree must be clean for :w-squash (agent leftovers would tangle the
-- rebase). Binary files are skipped; deleted files show content on the left
-- only. `?` opens a lazygit-style keybinding menu.
local M = {}

local gitwrite = require('user.git.write')

local augroup = vim.api.nvim_create_augroup('user.worktree.review', { clear = true })
local ns = vim.api.nvim_create_namespace('user.worktree.review')
local state = nil -- populated by M.review, cleared by M.close
-- last commit shown in a review session; survives M.close so <leader>gcp
-- still works from a regular window. Cleared by a successful pick.
local last_reviewed = nil

--------------------------------------------------------------------------------
-- git helpers
--------------------------------------------------------------------------------

local function git(cwd, args, env)
  local res = vim.system(vim.list_extend({ 'git', '-C', cwd }, args), { env = env }):wait()
  return res.code, res.stdout or '', res.stderr or ''
end

local function git_ok(cwd, args, env)
  local code, out = git(cwd, args, env)
  if code ~= 0 then return nil end
  return out
end

local function chomp(s) return (s:gsub('\n+$', '')) end

-- Root of the MAIN worktree (the one holding the shared .git dir). Works from
-- inside any worktree of the repo.
local function main_root(from)
  local commondir = git_ok(from, { 'rev-parse', '--path-format=absolute', '--git-common-dir' })
  commondir = commondir and chomp(commondir)
  if not commondir or not commondir:match('/%.git$') then return nil end
  return commondir:sub(1, -6)
end

local function upstream_branch(wt)
  local override = vim.g.WorktreeReviewUpstream
  if type(override) == 'string'
    and git_ok(wt, { 'rev-parse', '--verify', '-q', 'refs/heads/' .. override }) then
    return override
  end
  for _, b in ipairs({ 'main', 'master' }) do
    if git_ok(wt, { 'rev-parse', '--verify', '-q', 'refs/heads/' .. b }) then return b end
  end
end

-- Commits on the worktree branch that upstream does not have, oldest first.
-- --cherry-pick excludes patch-equivalent commits, so a commit already
-- cherry-picked onto upstream (same content, different sha) counts as
-- upstreamed even before the worktree is rebased.
local function unupstreamed(wt, branch)
  local out = git_ok(wt, { 'rev-list', '--cherry-pick', '--right-only', '--reverse',
    '--no-merges', branch .. '...HEAD' })
  if not out or out == '' then return {} end
  return vim.split(chomp(out), '\n', { plain = true })
end

local function worktrees(root)
  local out = git_ok(root, { 'worktree', 'list', '--porcelain' })
  if not out then return {} end
  local prefix = root .. '/worktrees/'
  local found, cur = {}, nil
  for line in out:gmatch('[^\n]+') do
    local path = line:match('^worktree (.+)')
    if path then
      cur = path:sub(1, #prefix) == prefix and vim.fn.isdirectory(path) == 1 and {} or nil
      if cur then
        cur.path, cur.name = path, path:sub(#prefix + 1)
        table.insert(found, cur)
      end
    elseif cur then
      local ref = line:match('^branch refs/heads/(.+)')
      if ref then cur.branch = ref end
    end
  end
  return found
end

-- git-status-style wording: "3 commits ahead", "1 commit behind" (only when
-- nonzero), or "up to date"
local function ahead_behind(wt, branch)
  local ahead = #unupstreamed(wt, branch)
  local behind = tonumber(chomp(git_ok(wt, { 'rev-list', '--count', 'HEAD..' .. branch }) or '0')) or 0
  if ahead == 0 and behind == 0 then return 'up to date' end
  local parts = { ('%d %s ahead'):format(ahead, ahead == 1 and 'commit' or 'commits') }
  if behind > 0 then
    parts[#parts + 1] = ('%d %s behind'):format(behind, behind == 1 and 'commit' or 'commits')
  end
  return table.concat(parts, ', ')
end

local function commit_label(wt, sha, is_next)
  -- no author and a capped subject: the label must fit the picker float width
  local out = chomp(git_ok(wt, { 'log', '-1', '--format=%h%x1f%s%x1f%cr', sha }) or '')
  local h, subject, when = out:match('([^\x1f]*)\x1f([^\x1f]*)\x1f(.*)')
  subject = subject or ''
  if vim.fn.strdisplaywidth(subject) > 42 then
    subject = vim.fn.strcharpart(subject, 0, 41) .. '…'
  end
  return ('%s%s  %s  (%s)'):format(is_next and '▸ ' or '  ', h or sha:sub(1, 7), subject, when or '')
end

local function blob(wt, spec)
  local code, out = git(wt, { 'cat-file', 'blob', spec })
  if code ~= 0 then return nil end
  return out
end

local function is_binary(raw) return raw:sub(1, 8192):find('\0', 1, true) ~= nil end

-- Changed files of a commit: { rel, deleted }. Binary files are skipped
-- (counted in the second return). --no-renames keeps every record a flat
-- 'X<%z>path' pair.
local function changed_files(wt, sha)
  local out = git_ok(wt, { 'diff-tree', '--no-renames', '-r', '--root', '--no-commit-id',
    '--name-status', '-z', sha })
  if not out then return {}, 0 end
  local fields = {}
  for f in out:gmatch('[^%z]+') do table.insert(fields, f) end
  local files, skipped = {}, 0
  for i = 1, #fields, 2 do
    local status, rel = fields[i], fields[i + 1]
    if status == 'D' then
      table.insert(files, { rel = rel, deleted = true })
    else
      local content = blob(wt, sha .. ':' .. rel)
      if content and is_binary(content) then
        skipped = skipped + 1
      elseif content then
        table.insert(files, { rel = rel, deleted = false })
      end
    end
  end
  return files, skipped
end

local function write_file(path, data)
  local f = assert(io.open(path, 'wb'))
  f:write(data)
  f:close()
end

--------------------------------------------------------------------------------
-- rendering (GitSplit-style pairwise diff tab)
--------------------------------------------------------------------------------

local function raw_to_lines(raw)
  if raw == '' then return {} end
  local lines = vim.split(raw, '\n', { plain = true })
  if lines[#lines] == '' then table.remove(lines) end
  return lines
end

local function fill_scratch(buf, raw)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, raw_to_lines(raw))
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

local function banner(buf, text)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if text then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_lines = { { { text, 'WarningMsg' } } },
      virt_lines_above = true,
      priority = 200,
    })
  end
end

-- Redraw both panes: vim does not recompute diffs on its own when one side is
-- a scratch buffer, so poke the diff engine and invalidate the screen grids.
local function repaint()
  if not state then return end
  pcall(vim.cmd, 'diffupdate')
  for _, w in ipairs({ state.lhs_win, state.rhs_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim__redraw, { win = w, valid = false })
    end
  end
  pcall(vim.api.nvim__redraw, { flush = true })
end

local repaint_debounce
local function repaint_debounced()
  if repaint_debounce and not repaint_debounce:is_closing() then
    repaint_debounce:stop()
    repaint_debounce:close()
  end
  repaint_debounce = vim.defer_fn(function()
    repaint()
    vim.schedule(repaint)
  end, 150)
end

local function refresh()
  if not state then return end
  local file = state.files[state.index]
  if not file then return end

  -- leave diff mode on BOTH windows before swapping content, otherwise the
  -- diff engine keeps stale highlight state that diffupdate cannot recover
  for _, w in ipairs({ state.lhs_win, state.rhs_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_call, w, function() vim.cmd('diffoff') end)
    end
  end

  local rhs = state.rhs_bufs[state.index]
  if vim.api.nvim_win_is_valid(state.rhs_win) and vim.api.nvim_buf_is_valid(rhs) then
    vim.api.nvim_win_set_buf(state.rhs_win, rhs)
  end

  local parent_raw = blob(state.wt, state.sha .. '^:' .. file.rel)
  vim.bo[state.lhs_buf].modifiable = true
  if parent_raw then
    vim.api.nvim_buf_set_lines(state.lhs_buf, 0, -1, false, raw_to_lines(parent_raw))
    banner(state.lhs_buf, nil)
  else
    vim.api.nvim_buf_set_lines(state.lhs_buf, 0, -1, false, {})
    banner(state.lhs_buf, '[ added in this commit — no parent version ]')
  end
  vim.bo[state.lhs_buf].modifiable = false
  vim.bo[state.lhs_buf].syntax = vim.bo[rhs].filetype ~= '' and vim.bo[rhs].filetype
    or (vim.filetype.match({ filename = state.wt .. '/' .. file.rel }) or '')

  for _, w in ipairs({ state.lhs_win, state.rhs_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_call, w, function() vim.cmd('diffthis') end)
    end
  end

  if vim.api.nvim_win_is_valid(state.lhs_win) then
    vim.wo[state.lhs_win].winbar = '[parent] ' .. file.rel
      .. (parent_raw == nil and '  (new file)' or '')
  end
  if vim.api.nvim_win_is_valid(state.rhs_win) then
    vim.wo[state.rhs_win].winbar = ('[%s] %s  (%d/%d)'):format(
      state.short, file.rel, state.index, #state.files)
  end
  repaint()
  vim.schedule(repaint)
end

--------------------------------------------------------------------------------
-- menu (lazygit-style keybinding cheatsheet)
--------------------------------------------------------------------------------

local function menu_toggle()
  if not state then return end
  if state.menu_win and vim.api.nvim_win_is_valid(state.menu_win) then
    pcall(vim.api.nvim_win_close, state.menu_win, true)
    state.menu_win = nil
    return
  end
  local file = state.files[state.index]
  local lines = {
    (' %s  %s'):format(state.short, state.subject),
    (' file %d/%d: %s%s'):format(state.index, #state.files, file.rel,
      file.deleted and '  (deleted in this commit)' or ''),
    '',
    '  <leader>bn / <leader>bp   next / previous file',
    '  <leader>bd                skip this file',
    '  :w                        squash nits into the commit',
    '  <leader>gcp               cherry-pick onto ' .. state.branch,
    '  ?                         toggle this menu',
    '  q                         close review (left pane only)',
  }
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = width + 2
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  state.menu_win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = #lines,
    row = (vim.o.lines - #lines) / 2,
    col = (vim.o.columns - width) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' keybindings ',
    title_pos = 'center',
  })
  for _, k in ipairs({ 'q', '<Esc>', '?' }) do
    vim.keymap.set('n', k, menu_toggle, { buffer = buf, silent = true })
  end
end

M.menu_toggle = menu_toggle

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

-- Indices of files whose right pane carries unapplied nits. A buffer counts
-- once its `modified` flag is set OR :w was hit (BufWriteCmd clears `modified`
-- but records the nit here).
local function nit_indices()
  local idx = {}
  for i, f in ipairs(state.files) do
    if not f.deleted and (vim.bo[state.rhs_bufs[i]].modified or state.nits[state.rhs_bufs[i]]) then
      table.insert(idx, i)
    end
  end
  return idx
end

local function assert_clean(wt, what)
  if git_ok(wt, { 'status', '--porcelain' }) ~= '' then
    vim.notify(('WorktreeReview: worktree is dirty — commit/stash before %s'):format(what),
      vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Squash right-pane edits into the reviewed commit: build a patch in a temp
-- dir (blob vs buffer), apply 3-way onto the worktree (merges with any later
-- commits), commit --fixup, then autosquash-rebase it home.
function M.apply_nits()
  if not state then return end
  local idx = nit_indices()
  if #idx == 0 then return vim.notify('WorktreeReview: no nits to apply') end
  if not assert_clean(state.wt, 'applying nits') then return end

  local tmp = vim.fn.tempname()
  local patches = {}
  for _, i in ipairs(idx) do
    local f = state.files[i]
    local old = blob(state.wt, state.sha .. ':' .. f.rel) or ''
    local new = table.concat(vim.api.nvim_buf_get_lines(state.rhs_bufs[i], 0, -1, false), '\n')
    if old:sub(-1) == '\n' then new = new .. '\n' end
    vim.fn.mkdir(vim.fs.dirname(tmp .. '/a/' .. f.rel), 'p')
    vim.fn.mkdir(vim.fs.dirname(tmp .. '/b/' .. f.rel), 'p')
    write_file(tmp .. '/a/' .. f.rel, old)
    write_file(tmp .. '/b/' .. f.rel, new)
    -- exit code 1 means "files differ" (the patch we want), 0 = identical.
    -- Empty --src/--dst prefixes keep the header paths at a/<rel> b/<rel>,
    -- which is what `git apply` in the worktree expects.
    local code, diff = git(tmp, { 'diff', '--no-index', '--src-prefix=', '--dst-prefix=',
      '--', 'a/' .. f.rel, 'b/' .. f.rel })
    if code == 1 then table.insert(patches, diff) end
  end
  if #patches == 0 then
    for _, i in ipairs(idx) do vim.bo[state.rhs_bufs[i]].modified = false end
    state.nits = {}
    return vim.notify('WorktreeReview: no textual changes')
  end

  local patchfile = tmp .. '/nits.patch'
  write_file(patchfile, table.concat(patches))
  local code, _, err = git(state.wt, { 'apply', '--3way', patchfile })
  if code ~= 0 then
    -- tree was verified clean, so restoring HEAD loses nothing of the user's
    git(state.wt, { 'reset', '--hard' })
    return vim.notify('WorktreeReview: nits conflicted with later commits:\n' .. err,
      vim.log.levels.ERROR)
  end

  local addargs = { 'add', '--' }
  for _, i in ipairs(idx) do table.insert(addargs, state.files[i].rel) end
  git(state.wt, addargs)
  code, _, err = git(state.wt, { 'commit', '--fixup=' .. state.sha })
  if code ~= 0 then
    git(state.wt, { 'reset', '--hard' })
    return vim.notify('WorktreeReview: fixup commit failed:\n' .. err, vim.log.levels.ERROR)
  end

  local parent = git_ok(state.wt, { 'rev-parse', state.sha .. '^' })
  local rebaseargs = parent and { 'rebase', '-i', '--autosquash', chomp(parent) }
    or { 'rebase', '-i', '--autosquash', '--root' }
  code, _, err = git(state.wt, rebaseargs, { GIT_SEQUENCE_EDITOR = ':', GIT_EDITOR = ':' })
  if code ~= 0 then
    return vim.notify('WorktreeReview: autosquash rebase stopped — resolve and '
      .. '`git rebase --continue`:\n' .. err, vim.log.levels.ERROR)
  end

  -- the rebase rewrote shas; find the squashed commit by its (preserved)
  -- subject, falling back to the oldest un-upstreamed commit
  local new_sha
  local log = git_ok(state.wt, { 'log', '--format=%H %s', state.branch .. '..HEAD' }) or ''
  for line in log:gmatch('[^\n]+') do
    if line:sub(42) == state.subject then new_sha = line:sub(1, 40) break end
  end
  new_sha = new_sha or unupstreamed(state.wt, state.branch)[1]
  -- the nits are committed; the scratch buffers are spent, so a following
  -- close/reopen must not prompt about "unsaved nits"
  for _, b in ipairs(state.rhs_bufs) do vim.bo[b].modified = false end
  state.nits = {}
  vim.notify(('WorktreeReview: nits squashed into %s → %s'):format(state.short, new_sha:sub(1, 7)))
  return true, new_sha
end

-- Shared pick: cherry-pick `entry.sha` (fields: root, branch, sha, wt) onto
-- the upstream branch checked out in the main worktree. Just the pick —
-- conflicts are resolved by hand in the main worktree, and patch-id tracking
-- means the commit leaves the queue even before the worktree is rebased.
local function cherry_pick_onto_upstream(entry)
  local head = chomp(git_ok(entry.root, { 'symbolic-ref', '--short', 'HEAD' }) or '')
  if head ~= entry.branch then
    return vim.notify(('WorktreeReview: main worktree (%s) is on %s — switch it to %s first')
      :format(entry.root, head ~= '' and head or 'a detached HEAD', entry.branch),
      vim.log.levels.ERROR)
  end
  local code, _, err = git(entry.root, { 'cherry-pick', entry.sha })
  if code ~= 0 then
    return vim.notify(('WorktreeReview: cherry-pick onto %s failed:\n%s\nresolve in %s '
      .. '(or `git cherry-pick --abort`), then retry'):format(entry.branch, err, entry.root),
      vim.log.levels.ERROR)
  end
  return true, unupstreamed(entry.wt, entry.branch)[1]
end

function M.upstream_commit()
  if not state then return end
  local ok, next_sha = cherry_pick_onto_upstream(state)
  if not ok then return end
  last_reviewed = nil -- consumed: the commit is on upstream now
  return true, next_sha
end

-- <leader>gcp from any window: pick the last reviewed commit. Errors loudly
-- when nothing has been reviewed (or the last pick consumed it).
function M.cherry_pick_last()
  if not last_reviewed then
    return vim.notify('WorktreeReview: nothing reviewed to cherry-pick yet',
      vim.log.levels.ERROR)
  end
  local entry = last_reviewed
  local ok = cherry_pick_onto_upstream(entry)
  if not ok then return end
  last_reviewed = nil
  vim.notify(('WorktreeReview: cherry-picked %s onto %s'):format(entry.short, entry.branch))
end

--------------------------------------------------------------------------------
-- navigation + lifecycle
--------------------------------------------------------------------------------

local function goto_index(i)
  if not state or #state.files == 0 then return end
  state.index = ((i - 1) % #state.files) + 1
  refresh()
end

local function next_file() goto_index((state and state.index or 1) + 1) end
local function prev_file() goto_index((state and state.index or 1) - 1) end

local function on_rhs_deleted(bufnr)
  if not state then return end
  for i, b in ipairs(state.rhs_bufs) do
    if b == bufnr then
      table.remove(state.files, i)
      table.remove(state.rhs_bufs, i)
      if i < state.index then state.index = state.index - 1 end
      break
    end
  end
  if #state.files == 0 then return vim.schedule(function() M.close(true) end) end
  if state.index > #state.files then state.index = #state.files end
  refresh()
end

local function skip_current()
  if not state then return end
  local i = state.index
  local b = state.rhs_bufs[i]
  table.remove(state.files, i)
  table.remove(state.rhs_bufs, i)
  if #state.files == 0 then return M.close(true) end
  if state.index > #state.files then state.index = #state.files end
  refresh()
  pcall(vim.cmd, 'bwipe! ' .. b)
end

-- Close the session. Returns false when the user keeps unsaved nits.
function M.close(force)
  local s = state
  if not s then return true end
  if not force and #nit_indices() > 0 then
    local choice = vim.fn.confirm(
      ('WorktreeReview: discard nits in %d file(s)?'):format(#nit_indices()),
      '&Discard\n&Cancel', 2)
    if choice ~= 1 then return false end
  end
  state = nil

  if s.menu_win and vim.api.nvim_win_is_valid(s.menu_win) then
    pcall(vim.api.nvim_win_close, s.menu_win, true)
  end

  local mine = { [s.lhs_win] = true, [s.rhs_win] = true }
  local has_user_wins = false
  if vim.api.nvim_tabpage_is_valid(s.tab) then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(s.tab)) do
      if not mine[w] then has_user_wins = true; break end
    end
  end

  for _, w in ipairs({ s.lhs_win, s.rhs_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_call, w, function() vim.cmd('diffoff') end)
    end
  end

  if has_user_wins then
    for _, w in ipairs({ s.lhs_win, s.rhs_win }) do
      if vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
    end
  elseif vim.api.nvim_tabpage_is_valid(s.tab) then
    pcall(vim.cmd, 'tabclose! ' .. vim.api.nvim_tabpage_get_number(s.tab))
  end

  for _, b in ipairs({ s.lhs_buf, unpack(s.rhs_bufs) }) do
    if vim.api.nvim_buf_is_valid(b) then pcall(vim.cmd, 'bwipe! ' .. b) end
  end
  vim.api.nvim_clear_autocmds({ group = augroup })
  return true
end

local function session_keymaps(b)
  local o = { buffer = b, silent = true }
  vim.keymap.set('n', '<leader>bn', next_file, o)
  vim.keymap.set('n', '<leader>bp', prev_file, o)
  vim.keymap.set('n', '<leader>bd', skip_current, o)
  vim.keymap.set('n', '?', menu_toggle, o)
  vim.keymap.set('n', '<leader>gcp', function()
    local wt, branch = state.wt, state.branch
    local ok, next_sha = M.upstream_commit()
    if not ok then return end
    vim.schedule(function()
      if not M.close() then return end
      if next_sha then
        M.review(wt, next_sha, branch)
      else
        vim.notify('WorktreeReview: worktree fully upstreamed — rebase or '
          .. '`git worktree remove ' .. wt .. '` when done')
      end
    end)
  end, o)
end

function M.review(wt, sha, branch)
  branch = branch or upstream_branch(wt)
  if not branch then
    return vim.notify('WorktreeReview: no main/master branch found', vim.log.levels.ERROR)
  end
  local files, skipped_bin = changed_files(wt, sha)
  if skipped_bin > 0 then
    vim.notify(('WorktreeReview: %d binary file(s) skipped'):format(skipped_bin))
  end
  if #files == 0 then
    return vim.notify('WorktreeReview: nothing reviewable in ' .. sha:sub(1, 7))
  end
  if state and not M.close() then return end

  local subject = chomp(git_ok(wt, { 'log', '-1', '--format=%s', sha }) or '')
  local short = chomp(git_ok(wt, { 'rev-parse', '--short', sha }) or sha)

  local lhs_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[lhs_buf].buftype = 'nofile'
  vim.bo[lhs_buf].bufhidden = 'hide'
  vim.bo[lhs_buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, lhs_buf, 'WorktreeReview://parent')

  local rhs_bufs = {}
  for _, f in ipairs(files) do
    -- NOT scratch: scratch buffers never take the 'modified' flag, which is
    -- how unapplied nits are tracked
    local b = vim.api.nvim_create_buf(false, false)
    vim.bo[b].bufhidden = 'hide'
    vim.bo[b].buflisted = true
    vim.bo[b].swapfile = false
    pcall(vim.api.nvim_buf_set_name, b, ('WorktreeReview://%s/%s'):format(short, f.rel))
    fill_scratch(b, f.deleted and '' or (blob(wt, sha .. ':' .. f.rel) or ''))
    vim.bo[b].modifiable = not f.deleted
    if f.deleted then banner(b, '[ deleted in this commit ]') end
    vim.bo[b].filetype = vim.filetype.match({ filename = wt .. '/' .. f.rel }) or ''
    table.insert(rhs_bufs, b)
  end

  vim.cmd('tabnew')
  local junk = vim.api.nvim_get_current_buf()
  local lhs_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(lhs_win, lhs_buf)
  if vim.api.nvim_buf_is_valid(junk) and junk ~= lhs_buf then
    pcall(vim.cmd, 'bwipe ' .. junk)
  end
  vim.cmd('rightbelow vsplit')
  local rhs_win = vim.api.nvim_get_current_win()

  state = {
    wt = wt,
    root = main_root(wt),
    branch = branch,
    sha = sha,
    short = short,
    subject = subject,
    files = files,
    rhs_bufs = rhs_bufs,
    nits = {},
    lhs_buf = lhs_buf,
    lhs_win = lhs_win,
    rhs_win = rhs_win,
    index = 1,
    tab = vim.api.nvim_get_current_tabpage(),
  }
  last_reviewed = { wt = wt, root = state.root, branch = branch, sha = sha, short = short }

  vim.api.nvim_clear_autocmds({ group = augroup })
  session_keymaps(lhs_buf)
  for _, b in ipairs(rhs_bufs) do
    session_keymaps(b)
    vim.api.nvim_create_autocmd('BufDelete', {
      group = augroup, buffer = b,
      callback = function() vim.schedule(function() on_rhs_deleted(b) end) end,
    })
    -- :w on the virtual buffer means "squash my nits into the commit"
    gitwrite.squash_on_write(augroup, b, state,
      function(buf)
        -- only changed writes count; a bare :w stays a no-op
        if vim.bo[buf].modified then state.nits[buf] = true end
      end,
      function()
        if not state or #nit_indices() == 0 then return end
        local wt, branch = state.wt, state.branch
        local ok, new_sha = M.apply_nits()
        if ok and new_sha then M.review(wt, new_sha, branch) end
      end)
    if vim.bo[b].modifiable then
      vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
        group = augroup, buffer = b,
        callback = function() repaint(); vim.schedule(repaint) end,
      })
      vim.api.nvim_create_autocmd('TextChangedI', {
        group = augroup, buffer = b,
        callback = repaint_debounced,
      })
    end
  end
  vim.keymap.set('n', 'q', function() M.close() end, { buffer = lhs_buf, silent = true })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = augroup,
    callback = function()
      if state and not vim.api.nvim_tabpage_is_valid(state.tab) then M.close(true) end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local win = tonumber(args.match)
      if state and (win == state.lhs_win or win == state.rhs_win) then M.close(true) end
    end,
  })

  refresh()
  if vim.api.nvim_win_is_valid(rhs_win) then
    vim.api.nvim_set_current_win(rhs_win)
  end
end

-- Exposed for tests / scripting.
function M.session() return state end

function M.start()
  local root = main_root(vim.uv.cwd())
  if not root then
    return vim.notify('WorktreeReview: not inside a git repository', vim.log.levels.ERROR)
  end
  local wts = {}
  for _, w in ipairs(worktrees(root)) do
    local label = 'worktrees/' .. w.name .. '/'
    local branch = upstream_branch(w.path)
    if branch then label = label .. '  ·  ' .. ahead_behind(w.path, branch) end
    if git_ok(w.path, { 'status', '--porcelain' }) ~= '' then label = label .. '  ·  dirty' end
    table.insert(wts, { path = w.path, label = label })
  end
  if #wts == 0 then
    return vim.notify('WorktreeReview: no worktrees under ' .. root .. '/worktrees/')
  end

  vim.ui.select(wts, {
    prompt = 'Worktree to review:',
    format_item = function(w) return w.label end,
  }, function(w)
    if not w then return end
    local branch = upstream_branch(w.path)
    local shas = branch and unupstreamed(w.path, branch) or {}
    if #shas == 0 then
      return vim.notify(('WorktreeReview: %s has nothing ahead of %s')
        :format(w.path, branch or 'main'))
    end
    local items = {}
    for i, s in ipairs(shas) do items[i] = { sha = s, label = commit_label(w.path, s, i == 1) } end
    vim.ui.select(items, {
      prompt = 'Commit to review (oldest first):',
      format_item = function(c) return c.label end,
    }, function(c)
      if c then M.review(w.path, c.sha, branch) end
    end)
  end)
end

vim.api.nvim_create_user_command('WorktreeReview', function() M.start() end, {})
vim.keymap.set('n', '<leader>gS', M.start,
  { desc = 'WorktreeReview: pick worktree + commit to review' })
vim.keymap.set('n', '<leader>gcp', M.cherry_pick_last,
  { desc = 'WorktreeReview: cherry-pick the last reviewed commit onto upstream' })

return M
