-- WorktreeReview: review-and-upstream queue for agent worktrees.
--
--   <leader>gS  pick a worktree under <root>/worktrees/ -> pick commits
--               (multi-select, oldest un-upstreamed first) -> review tab
--
-- The review tab mirrors GitSplit: left = selection^ (state before the
-- selected range), right = newest selected commit, one file pair at a time.
-- The right pane is an editable virtual buffer: edit it and :w — the edits
-- become a "WIP: human edits" commit on top of the selection (defer the
-- fixing to the agent), and it re-opens for a second look. WIP commits are
-- ordinary commits: they show in the queue and can be picked as-is; they are
-- only special as the session's `aux` — a :w-created edit commit that
-- <leader>gcp folds into the last pick so upstream stays clean.
-- <leader>gcp cherry-picks onto the upstream branch in the main worktree —
-- the pick only; no worktree rebase, conflicts are resolved by hand. The
-- queue tracks picks by patch-id, so picked commits drop out even before the
-- worktree is rebased onto upstream. <leader>gcp also works OUTSIDE the
-- session (any window): it picks the last reviewed commits; the pointer
-- clears on a successful pick.
--
-- The worktree must be clean for :w (agent leftovers would tangle the
-- replay). Binary files are skipped; deleted files show content on the left
-- only. `?` opens a lazygit-style keybinding menu.
local M = {}

local gitwrite = require('user.git.write')

local WIP_SUBJECT = 'WIP: human edits'
local EMPTY_TREE = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

local augroup = vim.api.nvim_create_augroup('user.worktree.review', { clear = true })
local ns = vim.api.nvim_create_namespace('user.worktree.review')
local state = nil -- populated by M.review, cleared by M.close
-- last selection shown in a review session ({ commits, aux }); survives
-- M.close so <leader>gcp still works from a regular window. Cleared by a
-- successful pick.
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

-- Changed files across a commit range base..newest: { rel, deleted }.
-- Binary files are skipped (counted in the second return). --no-renames
-- keeps every record a flat 'X<%z>path' pair.
local function changed_files(wt, base, newest)
  local out = git_ok(wt, { 'diff-tree', '--no-renames', '-r', '--no-commit-id',
    '--name-status', '-z', base, newest })
  if not out then return {}, 0 end
  local fields = {}
  for f in out:gmatch('[^%z]+') do table.insert(fields, f) end
  local files, skipped = {}, 0
  for i = 1, #fields, 2 do
    local status, rel = fields[i], fields[i + 1]
    if status == 'D' then
      table.insert(files, { rel = rel, deleted = true })
    else
      local content = blob(wt, newest .. ':' .. rel)
      if content and is_binary(content) then
        skipped = skipped + 1
      elseif content then
        table.insert(files, { rel = rel, deleted = false })
      end
    end
  end
  return files, skipped
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

  local parent_raw = blob(state.wt, state.base_sha .. ':' .. file.rel)
  vim.bo[state.lhs_buf].modifiable = true
  if parent_raw then
    vim.api.nvim_buf_set_lines(state.lhs_buf, 0, -1, false, raw_to_lines(parent_raw))
    banner(state.lhs_buf, nil)
  else
    vim.api.nvim_buf_set_lines(state.lhs_buf, 0, -1, false, {})
    banner(state.lhs_buf, '[ added — not present before the selection ]')
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
    vim.wo[state.lhs_win].winbar = '[base] ' .. file.rel
      .. (parent_raw == nil and '  (new file)' or '')
  end
  if vim.api.nvim_win_is_valid(state.rhs_win) then
    vim.wo[state.rhs_win].winbar = ('[%s] %s  (%d/%d)'):format(
      state.range_short, file.rel, state.index, #state.files)
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
    '  :w                        commit nits ("WIP: human edits")',
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

-- Record right-pane edits as a "WIP: human edits" commit parented on the
-- reviewed commit (a WIP under review, or an existing WIP child of the base,
-- is replaced in place); the rest of the branch replays on top, so conflicts
-- with later commits surface during the replay and are resolved by hand.
function M.commit_nits()
  if not state then return end
  local idx = nit_indices()
  if #idx == 0 then return vim.notify('WorktreeReview: no nits to apply') end
  if not assert_clean(state.wt, 'committing nits') then return end

  -- base = the real commit the nits annotate; marker = what the branch is
  -- cut at for the replay
  local base = state.sha
  if state.subject == WIP_SUBJECT then
    base = chomp(git_ok(state.wt, { 'rev-parse', state.sha .. '^' }) or '')
    if base == '' then
      return vim.notify('WorktreeReview: WIP commit has no parent', vim.log.levels.ERROR)
    end
  end
  local marker = base
  local after = git_ok(state.wt, { 'rev-list', '--reverse', '--no-merges', base .. '..HEAD' }) or ''
  if after ~= '' then
    local first_after = vim.split(chomp(after), '\n', { plain = true })[1]
    local subject = chomp(git_ok(state.wt, { 'log', '-1', '--format=%s', first_after }) or '')
    if subject == WIP_SUBJECT then marker = first_after end
  end

  -- build the WIP tree in a scratch index (the worktree's real index is
  -- never touched): base's tree with the edited buffers swapped in
  local scratch_env = { GIT_INDEX_FILE = vim.fn.tempname() }
  local code, _, err = git(state.wt, { 'read-tree', base }, scratch_env)
  if code ~= 0 then
    return vim.notify('WorktreeReview: read-tree failed:\n' .. err, vim.log.levels.ERROR)
  end
  for _, i in ipairs(idx) do
    local f = state.files[i]
    local content = table.concat(vim.api.nvim_buf_get_lines(state.rhs_bufs[i], 0, -1, false), '\n')
    if (blob(state.wt, base .. ':' .. f.rel) or ''):sub(-1) == '\n' then content = content .. '\n' end
    local res = vim.system({ 'git', '-C', state.wt, 'hash-object', '-w', '--stdin' },
      { stdin = content }):wait()
    if res.code ~= 0 then
      return vim.notify('WorktreeReview: hash-object failed:\n' .. (res.stderr or ''),
        vim.log.levels.ERROR)
    end
    local mode = (git_ok(state.wt, { 'ls-tree', base, '--', f.rel }) or ''):match('^(%d+)')
    git(state.wt, { 'update-index', '--add', '--cacheinfo',
      (mode or '100644') .. ',' .. chomp(res.stdout) .. ',' .. f.rel }, scratch_env)
  end
  local tree = git_ok(state.wt, { 'write-tree' }, scratch_env)
  local wip = tree and git_ok(state.wt, { 'commit-tree', chomp(tree), '-p', base, '-m', WIP_SUBJECT })
  if not wip then
    return vim.notify('WorktreeReview: could not build the WIP commit', vim.log.levels.ERROR)
  end
  wip = chomp(wip)

  -- nothing above the marker: move the branch; otherwise replay the rest
  local head = chomp(git_ok(state.wt, { 'rev-parse', 'HEAD' }) or '')
  if head == marker then
    git(state.wt, { 'reset', '--hard', wip })
  else
    code, _, err = git(state.wt, { 'rebase', '--onto', wip, marker },
      { GIT_SEQUENCE_EDITOR = ':', GIT_EDITOR = ':' })
    if code ~= 0 then
      return vim.notify('WorktreeReview: branch replay stopped — resolve and '
        .. '`git rebase --continue`:\n' .. err, vim.log.levels.ERROR)
    end
  end

  -- the nits are committed; the scratch buffers are spent, so a following
  -- close/reopen must not prompt about "unsaved nits"
  for _, b in ipairs(state.rhs_bufs) do vim.bo[b].modified = false end
  state.nits = {}
  vim.notify(('WorktreeReview: nits committed as %s ("%s")'):format(wip:sub(1, 7), WIP_SUBJECT))
  return true, wip
end

-- Shared pick: cherry-pick `entry.commits` (fields: root, branch, commits,
-- wt, aux) onto the upstream branch checked out in the main worktree, in
-- order; `aux` (a :w-created edit commit) is folded into the LAST pick so
-- upstream receives clean commits. Just picks — conflicts are resolved by
-- hand in the main worktree. Patch-id tracking means plain picks leave the
-- queue even before the worktree is rebased.
local function cherry_pick_onto_upstream(entry)
  local head = chomp(git_ok(entry.root, { 'symbolic-ref', '--short', 'HEAD' }) or '')
  if head ~= entry.branch then
    return vim.notify(('WorktreeReview: main worktree (%s) is on %s — switch it to %s first')
      :format(entry.root, head ~= '' and head or 'a detached HEAD', entry.branch),
      vim.log.levels.ERROR)
  end
  for _, sha in ipairs(entry.commits) do
    local code, _, err = git(entry.root, { 'cherry-pick', sha })
    if code ~= 0 then
      return vim.notify(('WorktreeReview: cherry-pick %s onto %s failed:\n%s\nresolve in %s '
        .. '(or `git cherry-pick --abort`), then retry')
        :format(sha:sub(1, 7), entry.branch, err, entry.root), vim.log.levels.ERROR)
    end
    if entry.picked then entry.picked[sha] = true end
  end
  if entry.aux then
    local code, _, err = git(entry.root, { 'cherry-pick', '-n', entry.aux })
    if code ~= 0 then
      return vim.notify(('WorktreeReview: folding %s into the pick conflicted:\n%s\n'
        .. '`git cherry-pick --abort` in %s undoes just the fold (the picks stay)')
        :format(WIP_SUBJECT, err, entry.root), vim.log.levels.ERROR)
    end
    code, _, err = git(entry.root, { 'commit', '--amend', '--no-edit' })
    if code ~= 0 then
      return vim.notify('WorktreeReview: amending the pick failed:\n' .. err, vim.log.levels.ERROR)
    end
    -- the folded pick is NOT patch-equivalent to the base commit, so the
    -- queue cannot drop the pair on its own
    if entry.picked then entry.picked[entry.aux] = true end
  end
  -- next in queue, skipping anything picked this session
  local picked = entry.picked or {}
  local next_sha
  for _, s in ipairs(unupstreamed(entry.wt, entry.branch)) do
    if not picked[s] then next_sha = s break end
  end
  return true, next_sha
end

function M.upstream_commit()
  if not state then return end
  local ok, next_sha = cherry_pick_onto_upstream(state)
  if not ok then return end
  last_reviewed = nil -- consumed: the commit is on upstream now
  return true, next_sha
end

-- <leader>gcp from any window: pick the last reviewed selection. Errors
-- loudly when nothing has been reviewed (or the last pick consumed it).
function M.cherry_pick_last()
  if not last_reviewed then
    return vim.notify('WorktreeReview: nothing reviewed to cherry-pick yet',
      vim.log.levels.ERROR)
  end
  local entry = last_reviewed
  local ok = cherry_pick_onto_upstream(entry)
  if not ok then return end
  last_reviewed = nil
  local n = #entry.commits + (entry.aux and 1 or 0)
  vim.notify(('WorktreeReview: cherry-picked %d commit(s) onto %s'):format(n, entry.branch))
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
        vim.notify('WorktreeReview: worktree fully upstreamed — `git rebase '
          .. branch .. '` in ' .. wt .. ' clears the queue (or `git worktree remove` it)')
      end
    end)
  end, o)
end

-- Review a contiguous selection of commits (oldest-first list, or a single
-- sha string). `aux` marks the last entry as a :w-created edit commit: it is
-- excluded from the pick list so <leader>gcp folds it into the last pick
-- instead of cherry-picking it separately.
function M.review(wt, shas, branch, aux)
  if type(shas) == 'string' then shas = { shas } end
  branch = branch or upstream_branch(wt)
  if not branch then
    return vim.notify('WorktreeReview: no main/master branch found', vim.log.levels.ERROR)
  end
  if #shas == 0 then return vim.notify('WorktreeReview: empty selection') end
  local newest = shas[#shas]
  local base = chomp(git_ok(wt, { 'rev-parse', shas[1] .. '^' }) or '')
  if base == '' then base = EMPTY_TREE end

  local files, skipped_bin = changed_files(wt, base, newest)
  if skipped_bin > 0 then
    vim.notify(('WorktreeReview: %d binary file(s) skipped'):format(skipped_bin))
  end
  if #files == 0 then
    return vim.notify('WorktreeReview: nothing reviewable in ' .. shas[1]:sub(1, 7))
  end
  if state and not M.close() then return end

  local subject = chomp(git_ok(wt, { 'log', '-1', '--format=%s', newest }) or '')
  local short = chomp(git_ok(wt, { 'rev-parse', '--short', newest }) or newest)
  local range_short = short
  if #shas > 1 then
    range_short = chomp(git_ok(wt, { 'rev-parse', '--short', shas[1] }) or shas[1]) .. '..' .. short
  end
  local commits = aux and vim.list_slice(shas, 1, #shas - 1) or vim.list_slice(shas)

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
    fill_scratch(b, f.deleted and '' or (blob(wt, newest .. ':' .. f.rel) or ''))
    vim.bo[b].modifiable = not f.deleted
    if f.deleted then banner(b, '[ deleted in this selection ]') end
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
    shas = shas,
    base_sha = base,
    commits = commits,
    aux = aux,
    sha = newest,
    short = short,
    range_short = range_short,
    subject = subject,
    files = files,
    rhs_bufs = rhs_bufs,
    nits = {},
    picked = {}, -- shas already picked onto upstream this session (a folded
                 -- pick is not patch-equivalent, so it lingers in the queue
                 -- until the worktree is rebased)
    lhs_buf = lhs_buf,
    lhs_win = lhs_win,
    rhs_win = rhs_win,
    index = 1,
    tab = vim.api.nvim_get_current_tabpage(),
  }
  last_reviewed = { wt = wt, root = state.root, branch = branch, commits = commits,
    aux = aux, short = short, subject = subject }

  vim.api.nvim_clear_autocmds({ group = augroup })
  session_keymaps(lhs_buf)
  for _, b in ipairs(rhs_bufs) do
    session_keymaps(b)
    vim.api.nvim_create_autocmd('BufDelete', {
      group = augroup, buffer = b,
      callback = function() vim.schedule(function() on_rhs_deleted(b) end) end,
    })
    -- :w on the virtual buffer means "commit my nits into the worktree"
    gitwrite.on_write(augroup, b, state,
      function(buf)
        -- only changed writes count; a bare :w stays a no-op
        if vim.bo[buf].modified then state.nits[buf] = true end
      end,
      function()
        if not state or #nit_indices() == 0 then return end
        local wt, branch = state.wt, state.branch
        local had_aux = state.aux
        local shas = vim.list_slice(state.shas)
        local ok, wip = M.commit_nits()
        if ok and wip then
          -- reviewing the selection's own aux replaces it in the last slot
          if had_aux then shas[#shas] = wip else shas[#shas + 1] = wip end
          M.review(wt, shas, branch, wip)
        end
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

-- Multi-select commit picker float: space toggles, a toggles all, enter
-- reviews (the cursor line when nothing is toggled), q/Esc cancels. The
-- selection must be contiguous in queue order — a range is the only shape
-- with a coherent single diff.
local function pick_commits(wt, branch)
  local queue = unupstreamed(wt, branch)
  if #queue == 0 then
    return vim.notify(('WorktreeReview: nothing ahead of %s in %s'):format(branch, wt))
  end
  local labels = {}
  local width = 12
  for i, s in ipairs(queue) do
    labels[i] = commit_label(wt, s, i == 1)
    width = math.max(width, vim.fn.strdisplaywidth(labels[i]) + 6)
  end
  width = math.min(width, 86)
  local height = math.min(#queue, math.max(3, math.floor(vim.o.lines * 0.6)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height,
    row = (vim.o.lines - height) / 2, col = (vim.o.columns - width) / 2,
    style = 'minimal', border = 'rounded',
    title = ' space toggle · a all · enter review · q cancel ',
    title_pos = 'center', footer = ' oldest first — selection must be contiguous ',
    footer_pos = 'center',
  })
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  local selected, cursor = {}, 1
  local function render()
    local lines = {}
    for i, l in ipairs(labels) do
      lines[i] = (selected[i] and '[x] ' or '[ ] ') .. l
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_cursor(win, { math.min(cursor, #queue), 0 })
  end

  local function confirm()
    local idx = {}
    for i in pairs(selected) do idx[#idx + 1] = i end
    if #idx == 0 then
      idx = { cursor }
    else
      table.sort(idx)
      for i = 2, #idx do
        if idx[i] ~= idx[i - 1] + 1 then
          return vim.notify('WorktreeReview: selection must be contiguous in queue order',
            vim.log.levels.WARN)
        end
      end
    end
    local shas = {}
    for k, i in ipairs(idx) do shas[k] = queue[i] end
    vim.api.nvim_win_close(win, true)
    M.review(wt, shas, branch)
  end

  local function move(d)
    cursor = math.min(math.max(cursor + d, 1), #queue)
    render()
  end

  local o = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set('n', 'j', function() move(1) end, o)
  vim.keymap.set('n', 'k', function() move(-1) end, o)
  vim.keymap.set('n', '<Down>', function() move(1) end, o)
  vim.keymap.set('n', '<Up>', function() move(-1) end, o)
  vim.keymap.set('n', '<Space>', function()
    selected[cursor] = not selected[cursor] or nil
    move(1)
  end, o)
  vim.keymap.set('n', 'a', function()
    local all = true
    for i = 1, #queue do
      if not selected[i] then all = false break end
    end
    selected = {}
    if not all then for i = 1, #queue do selected[i] = true end end
    render()
  end, o)
  vim.keymap.set('n', '<CR>', confirm, o)
  vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, o)
  vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(win, true) end, o)
  render()
end

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
    if not branch or #unupstreamed(w.path, branch) == 0 then
      return vim.notify(('WorktreeReview: %s has nothing ahead of %s')
        :format(w.path, branch or 'main'))
    end
    pick_commits(w.path, branch)
  end)
end

vim.api.nvim_create_user_command('WorktreeReview', function() M.start() end, {})
vim.keymap.set('n', '<leader>gS', M.start,
  { desc = 'WorktreeReview: pick worktree + commit to review' })
vim.keymap.set('n', '<leader>gcp', M.cherry_pick_last,
  { desc = 'WorktreeReview: cherry-pick the last reviewed commit onto upstream' })

return M
