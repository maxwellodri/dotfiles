-- WorktreeReview: review agent-worktree commits on the real files of the
-- upstream branch, then merge them or hand edits back to the agent.
--
--   <leader>gww (:WorktreeReview)  pick a worktree under <root>/worktrees/
--               -> its OLDEST commit not yet upstreamed is cherry-picked onto
--               the upstream branch in the main worktree -> a review tab
--               opens:
--                 top    2/3  the commit's files, editable — :w autostages
--                 bottom 1/3  read-only mirror of the shown file at the
--                              PRE-PICK state: same file, same filetype,
--                              diff-paired with the top pane
--               <leader>bn / <leader>bp cycle files (multi-file commits);
--               files the commit deleted have no editable buffer.
--   <leader>gwf (:WorktreeReviewFeedbackSubmission)  hand my edits back:
--               they are committed on main as "WIP: Human edits", rebased
--               into the worktree DIRECTLY AFTER the reviewed commit (later
--               worktree commits replay above it), and main is restored to
--               its pre-pick state. A ready-to-paste prompt for the agent is
--               copied to the + register (and kept in
--               vim.g.WorktreeReviewLastPrompt); on a conflicted rebase it
--               also opens in an editor buffer for tweaking.
--   <leader>gwc (:WorktreeReviewCommit)  commit my edits on main (merge
--               with my fixes): a prompt buffer opens — write AMEND to fold
--               them into the picked commit keeping the agent's subject, or
--               write a commit message for a new commit. # lines are
--               comments, an empty write cancels, and no edits = noop.
--
-- Reviewing happens on the real files in the main worktree, so grep / LSP /
-- anything else works; //nit: ... comments are ordinary edits. Closing the
-- session with undispatched edits asks: hand back / keep on main / discard
-- (Escape = leave everything as-is: pick stays on main, staged edits stay).
-- gf/gC shorthand below = <leader>gwf / <leader>gwc.
-- :WorktreeReviewCancel discards explicitly; the WIP commit always survives
-- on the refs/heads/worktree-review-wip backup ref.
--
-- Safety: a pick requires the main worktree on the upstream branch with
-- nothing staged and no dirty file the commit touches (unrelated dirty files
-- are fine — git cherry-picks around them). gf/gC refuse if main's HEAD
-- moved since the pick. gf rebases with --autostash so an agent mid-task in
-- the worktree does not block the handback; if the rebase stops on
-- conflicts it is left in place for the agent to finish (the prompt says
-- how) and the feedback survives on the backup ref.
local M = {}

--------------------------------------------------------------------------------
-- git helpers
--------------------------------------------------------------------------------

local function git(cwd, args)
  local res = vim.system(vim.list_extend({ 'git', '-C', cwd }, args)):wait()
  return res.code, res.stdout or '', res.stderr or ''
end

local function git_ok(cwd, args)
  local code, out = git(cwd, args)
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

local WIP_SUBJECT = 'WIP: Human edits'
local BACKUP_REF = 'refs/heads/worktree-review/wip'

-- Commits on the worktree branch that upstream does not have, oldest first.
-- --cherry-pick excludes patch-equivalent commits, so a commit already
-- cherry-picked onto upstream (same content, different sha) counts as
-- upstreamed even before the worktree is rebased. My own WIP feedback
-- commits are addressed to the agent, never reviewable — filtered out.
local function unupstreamed(wt, branch)
  local out = git_ok(wt, { 'rev-list', '--cherry-pick', '--right-only', '--reverse',
    '--no-merges', branch .. '...HEAD' })
  if not out or out == '' then return {} end
  local shas = vim.split(chomp(out), '\n', { plain = true })
  local queue = {}
  for _, s in ipairs(shas) do
    local subject = chomp(git_ok(wt, { 'show', '-s', '--format=%s', s }) or '')
    if subject ~= WIP_SUBJECT then queue[#queue + 1] = s end
  end
  return queue
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

-- repo-relative paths a commit touches
local function commit_paths(wt, sha)
  local out = git_ok(wt, { 'diff-tree', '--no-renames', '-r', '--no-commit-id',
    '--name-only', '-z', sha .. '^', sha }) or ''
  local paths = {}
  for p in out:gmatch('[^%z]+') do paths[#paths + 1] = p end
  return paths
end

-- staged and dirty (incl. untracked) paths of a worktree, as sets
local function status_sets(root)
  local res = vim.system({ 'git', '-C', root, 'status', '--porcelain=v1',
    '--untracked-files=all', '-z', '--no-renames' }):wait()
  local raw = (res and res.code == 0 and res.stdout) or ''
  local staged, dirty = {}, {}
  for entry in raw:gmatch('[^%z]+') do
    local x, y, path = entry:sub(1, 1), entry:sub(2, 2), entry:sub(4)
    if x ~= ' ' and x ~= '?' then staged[path] = true end
    if x == '?' or y ~= ' ' then dirty[path] = true end
  end
  return staged, dirty
end

-- Heuristic: a file counts as "text" if its first chunk has no NUL byte —
-- the same rule vim and git use. Binary diffs are meaningless in a buffer.
local function is_text(path)
  local f = io.open(path, 'rb')
  if not f then return false end
  local chunk = f:read(8192) or ''
  f:close()
  return chunk:find('\0', 1, true) == nil
end

--------------------------------------------------------------------------------
-- session state
--------------------------------------------------------------------------------

-- shas already cherry-picked this session. An amended pick is no longer
-- patch-equivalent, so the worktree's copy lingers in the queue until the
-- agent rebases the worktree — don't offer it twice per session.
local picked = {}

-- the live review session (mirrored into vim.g.WorktreeReviewSession for
-- observability from the cmdline / other tooling):
--   root, wt_path, wt_name, wt_branch     where the commit came from
--   base_sha                              main HEAD before the pick
--   commit_main_sha                       the pick, as it landed on main
--   commit_wt_sha                         the pick's original sha in the wt
--   files                                 { rel, abs, buf } editable files
local session
local augroup = vim.api.nvim_create_augroup('user.git.worktree', { clear = true })

local function set_session(s)
  session = s
  vim.g.WorktreeReviewSession = s and {
    root = s.root,
    wt_path = s.wt_path,
    wt_name = s.wt_name,
    wt_branch = s.wt_branch,
    base_sha = s.base_sha,
    commit_main_sha = s.commit_main_sha,
    commit_wt_sha = s.commit_wt_sha,
  } or nil
end

local function short(root, sha) return chomp(git_ok(root, { 'rev-parse', '--short', sha }) or sha) end

local function session_edits(s)
  -- staged or dirty state over the session's files = my undispatched edits
  local staged, dirty = status_sets(s.root)
  local edits, foreign = {}, {}
  for _, f in ipairs(s.files) do
    if staged[f.rel] or dirty[f.rel] then edits[#edits + 1] = f.rel end
  end
  for p in pairs(staged) do
    local is_session = false
    for _, f in ipairs(s.files) do if f.rel == p then is_session = true end end
    if not is_session then foreign[#foreign + 1] = p end
  end
  return edits, foreign
end

local function save_session_buffers(s)
  for _, f in ipairs(s.files) do
    if vim.api.nvim_buf_is_valid(f.buf) and vim.bo[f.buf].modified then
      pcall(vim.api.nvim_buf_call, f.buf, function() vim.cmd('silent write') end)
    end
  end
end

--------------------------------------------------------------------------------
-- the review tab: top 2/3 the commit's files (editable), bottom 1/3 a
-- read-only mirror of the shown file at the PRE-PICK state — same file, same
-- filetype, diff-paired, so the pair reads exactly like the earliest
-- WorktreeReview vsplit, only stacked
--------------------------------------------------------------------------------

local ns = vim.api.nvim_create_namespace('user.git.worktree')

local function rev_lines(root, rev, rel)
  local out = vim.fn.systemlist({ 'git', '-C', root, 'show', rev .. ':' .. rel })
  if vim.v.shell_error ~= 0 then return nil end
  for i, line in ipairs(out) do out[i] = line:gsub('\r$', '') end
  return out
end

-- recompute the diff pair and force both panes to repaint (vim will not
-- recompute diffs on its own with a nofile partner)
local function repaint(s)
  if not s or not vim.api.nvim_win_is_valid(s.old_win) then return end
  pcall(vim.cmd, 'diffupdate')
  for _, w in ipairs({ s.top_win, s.old_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim__redraw, { win = w, valid = false })
    end
  end
  pcall(vim.api.nvim__redraw, { flush = true })
end

local repaint_debounce
local function repaint_debounced(s)
  if repaint_debounce and not repaint_debounce:is_closing() then
    repaint_debounce:stop()
    repaint_debounce:close()
  end
  repaint_debounce = vim.defer_fn(function()
    repaint(s)
    vim.schedule(function() repaint(s) end)
  end, 150)
end

local function set_mirror_content(s)
  local f = s.files[s.index]
  -- diffoff BOTH windows before mutating: swapping content under diff mode
  -- corrupts the highlight model until the next diffupdate
  for _, w in ipairs({ s.top_win, s.old_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_call, w, function() vim.cmd('diffoff') end)
    end
  end
  vim.bo[s.old_buf].modifiable = true
  local banner
  if f.abs == '' then
    vim.api.nvim_buf_set_lines(s.old_buf, 0, -1, false, {})
  else
    local lines = rev_lines(s.root, s.base_sha, f.rel)
    if lines then
      vim.api.nvim_buf_set_lines(s.old_buf, 0, -1, false, lines)
    else
      vim.api.nvim_buf_set_lines(s.old_buf, 0, -1, false, {})
      banner = '[ new in this commit — no pre-pick version ]'
    end
  end
  vim.bo[s.old_buf].modifiable = false

  -- syntax (NOT filetype) so FileType autocmds do not fire on this nofile
  -- scratch on every file switch; syntax alone lights it up like the top pane
  local ft = (vim.api.nvim_buf_is_valid(f.buf) and vim.bo[f.buf].filetype) or ''
  if ft == '' and f.abs ~= '' then ft = vim.filetype.match({ filename = f.abs }) or '' end
  vim.bo[s.old_buf].syntax = ft

  vim.api.nvim_buf_clear_namespace(s.old_buf, ns, 0, -1)
  if banner then
    vim.api.nvim_buf_set_extmark(s.old_buf, ns, 0, 0, {
      virt_lines = { { { banner, 'WarningMsg' } } },
      virt_lines_above = true,
      priority = 200,
    })
  end

  for _, w in ipairs({ s.top_win, s.old_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_call, w, function() vim.cmd('diffthis') end)
    end
  end
  if vim.api.nvim_win_is_valid(s.old_win) then
    vim.wo[s.old_win].winbar = ('[%s] %s  ·  pre-pick, read-only (q closes the review)')
      :format(short(s.root, s.base_sha), f.rel)
  end
  repaint(s)
  vim.schedule(function() repaint(s) end)
end

local function goto_index(i)
  local s = session
  if not s or #s.files == 0 then return end
  s.index = ((i - 1) % #s.files) + 1
  local f = s.files[s.index]
  if vim.api.nvim_win_is_valid(s.top_win) and vim.api.nvim_buf_is_valid(f.buf) then
    vim.api.nvim_win_set_buf(s.top_win, f.buf)
  end
  if vim.api.nvim_win_is_valid(s.top_win) then
    vim.wo[s.top_win].winbar = ('review: %s  (%d/%d)  ·  \\gwf hand back · \\gwc commit · \\bn/\\bp files')
      :format(f.rel, s.index, #s.files)
  end
  set_mirror_content(s)
end

local function next_file() goto_index((session and session.index or 1) + 1) end
local function prev_file() goto_index((session and session.index or 1) - 1) end

-- teardown only — never prompts. Closes the tab, keeps the real file buffers
-- (still listed for further editing), wipes the scratch panes.
local function close_session()
  local s = session
  if not s then return end
  set_session(nil)
  vim.api.nvim_clear_autocmds({ group = augroup })
  -- a commit-prompt window outlives its purpose once the session ends
  if vim.api.nvim_win_is_valid(s.prompt_win or -1) then
    pcall(vim.api.nvim_win_close, s.prompt_win, true)
  end
  for _, f in ipairs(s.files) do
    if vim.api.nvim_buf_is_valid(f.buf) then
      pcall(vim.keymap.del, 'n', '<leader>bn', { buffer = f.buf })
      pcall(vim.keymap.del, 'n', '<leader>bp', { buffer = f.buf })
      pcall(vim.keymap.del, 'n', '<leader>gwf', { buffer = f.buf })
      pcall(vim.keymap.del, 'n', '<leader>gwc', { buffer = f.buf })
    end
  end
  if vim.api.nvim_buf_is_valid(s.old_buf) then
    pcall(vim.keymap.del, 'n', 'q', { buffer = s.old_buf })
    pcall(vim.keymap.del, 'n', '<leader>gwf', { buffer = s.old_buf })
    pcall(vim.keymap.del, 'n', '<leader>gwc', { buffer = s.old_buf })
  end
  for _, w in ipairs({ s.top_win, s.old_win }) do
    if vim.api.nvim_win_is_valid(w) then pcall(vim.api.nvim_win_close, w, true) end
  end
  if vim.api.nvim_buf_is_valid(s.old_buf) then pcall(vim.cmd, 'bwipe! ' .. s.old_buf) end
end

-- undo the pick (and my edits, once committed as `e_sha`) in the main
-- worktree, WITHOUT touching unrelated dirty files: remove files the commit
-- added while they are still tracked, move the branch back to base, then
-- restore only the touched paths. Session buffers are force-reloaded so a
-- later :w cannot resurrect the reverted state.
local function git_paths(cwd, verb, paths)
  -- pathspec-bearing commands: paths is a table, spread it — vim.system does
  -- not flatten nested args and a stray table silently becomes a missing
  -- pathspec (git commit -- then sweeps the whole index)
  return git(cwd, vim.list_extend(verb, paths))
end

local function restore_main_to_base(s, e_sha)
  local touched = vim.split(chomp(git_ok(s.root,
    { 'diff', '--no-renames', '--name-only', '-z', s.base_sha, e_sha }) or ''):gsub('%z', '\n'), '\n')
  local added = vim.split(chomp(git_ok(s.root,
    { 'diff', '--no-renames', '--name-only', '--diff-filter=A', '-z', s.base_sha, e_sha })
    or ''):gsub('%z', '\n'), '\n')
  local added_set = {}
  for _, p in ipairs(added) do if p ~= '' then added_set[p] = true end end
  local addable, restorable = {}, {}
  for _, p in ipairs(touched) do
    if p ~= '' then
      if added_set[p] then addable[#addable + 1] = p else restorable[#restorable + 1] = p end
    end
  end
  -- soft reset: a mixed one would also rewind FOREIGN staged index entries
  -- (unrelated partially-staged hunks), which we promise to leave alone
  local ok = true
  local fail = function(step, err)
    ok = false
    vim.notify(('WorktreeReview: restoring main failed at `%s` — main HEAD is %s; '
      .. 'the feedback is safe on ref %s\n%s'):format(step,
        short(s.root, chomp(git_ok(s.root, { 'rev-parse', 'HEAD' }) or 'HEAD')),
        BACKUP_REF, err or ''), vim.log.levels.ERROR)
  end
  if #addable > 0 then
    local c, _, e = git_paths(s.root, { 'rm', '-qf', '--' }, addable)
    if c ~= 0 then return fail('git rm', e) end
  end
  local c, _, e = git(s.root, { 'reset', '-q', '--soft', s.base_sha })
  if c ~= 0 then return fail('git reset', e) end
  if #restorable > 0 then
    local c2, _, e2 = git_paths(s.root,
      { 'restore', '--source=' .. s.base_sha, '--staged', '--worktree', '--' }, restorable)
    if c2 ~= 0 then return fail('git restore', e2) end
  end
  for _, f in ipairs(s.files) do
    if vim.api.nvim_buf_is_valid(f.buf) then
      if f.abs ~= '' and vim.fn.filereadable(f.abs) == 0 then
        -- added-by-the-commit file was rm'd: a kept buffer would resurrect
        -- it (empty) on the next :w
        pcall(vim.cmd, 'bwipe! ' .. f.buf)
      else
        pcall(vim.api.nvim_buf_call, f.buf, function() vim.cmd('silent! edit!') end)
      end
    end
  end
  return ok
end

local function deliver_agent_prompt(text)
  vim.g.WorktreeReviewLastPrompt = text
  pcall(vim.fn.setreg, '+', text)
end

-- conflicted handbacks need attention (and often a tweak or two): show the
-- prompt in an editable buffer next to the clipboard copy
local function show_note_buffer(name, title, text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  vim.bo[buf].filetype = 'markdown'
  vim.cmd('botright 12split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].winbar = title .. '  ·  q closes'
  vim.keymap.set('n', 'q', function()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.cmd, 'bwipe! ' .. buf)
  end, { buffer = buf, silent = true })
end

local function show_prompt_buffer(text)
  show_note_buffer('WorktreeReview-prompt',
    'agent prompt — also in the + register, edit freely', text)
end

local function agent_prompt_success(s, e_sha)
  return ('Review feedback for you in worktree %s: my commit "%s" (%s) is now inserted '
    .. 'directly after %s ("%s") on your branch.\n'
    .. 'Please address every `//nit:` comment and anything else you disagree with in that '
    .. 'commit, fix the code, remove the comment lines, and fold my WIP commit into the '
    .. 'commit it comments on (interactive rebase, fixup). Rebase the branch onto %s '
    .. 'afterwards if it has moved.'):format(s.wt_name, WIP_SUBJECT, short(s.root, e_sha),
    short(s.root, s.commit_wt_sha),
    chomp(git_ok(s.root, { 'show', '-s', '--format=%s', s.commit_wt_sha }) or ''),
    upstream_branch(s.wt_path) or 'the upstream branch')
end

local function agent_prompt_conflict(s, e_sha, conflicted, stashed)
  local t = ('Review feedback for you in worktree %s: I inserted my commit "%s" (%s) after '
    .. '%s ("%s"), but the rebase stopped on conflicts in your worktree:\n  %s\n'
    .. 'Resolve them keeping both the code and my comments where it makes sense, '
    .. 'then `git rebase --continue`. If you aborted the rebase instead, redo it with '
    .. '`git rebase --onto %s %s`. My full feedback is commit %s (also kept on the ref %s).')
    :format(s.wt_name, WIP_SUBJECT, short(s.root, e_sha), short(s.root, s.commit_wt_sha),
      chomp(git_ok(s.root, { 'show', '-s', '--format=%s', s.commit_wt_sha }) or ''),
      table.concat(conflicted, '\n  '), e_sha, s.commit_wt_sha, e_sha, BACKUP_REF)
  if stashed then
    t = t .. '\nYour uncommitted changes were autostashed; if the stash failed to pop after '
      .. 'the rebase, recover them with `git stash pop` / `git stash list`.'
  end
  return t .. '\nAfterwards address the nits, remove the comment lines, and fold my WIP '
    .. 'commit into the commit it comments on.'
end

--------------------------------------------------------------------------------
-- <leader>gwf: hand my edits back to the worktree
--------------------------------------------------------------------------------

function M.feedback()
  local s = session
  if not s then return vim.notify('WorktreeReview: no review session open') end
  save_session_buffers(s)
  local edits, foreign = session_edits(s)
  if #edits == 0 then
    return vim.notify('WorktreeReview: no edits to hand back')
  end
  local head = chomp(git_ok(s.root, { 'rev-parse', 'HEAD' }) or '')
  if head ~= s.commit_main_sha then
    return vim.notify(('WorktreeReview: main HEAD moved to %s ("%s") since the pick — '
      .. 'resolve that first'):format(short(s.root, head),
        chomp(git_ok(s.root, { 'show', '-s', '--format=%s', head }) or '')), vim.log.levels.ERROR)
  end
  -- the handback rebases the worktree's checked-out branch: a detached HEAD
  -- there would "succeed" while the agent's branch never moves
  local wt_head = chomp(git_ok(s.wt_path, { 'symbolic-ref', '--short', 'HEAD' }) or '')
  if s.wt_branch == nil or wt_head ~= s.wt_branch then
    return vim.notify(('WorktreeReview: %s is on %s, not %s — the WIP must land on the '
      .. 'branch; switch it back first'):format(s.wt_path, wt_head ~= '' and wt_head or 'a detached HEAD',
      s.wt_branch or 'its branch'), vim.log.levels.ERROR)
  end

  -- E carries exactly my session-file edits (pathspec-limited: anything else
  -- staged stays staged in main and never reaches the agent's branch)
  local paths = {}
  for _, f in ipairs(s.files) do paths[#paths + 1] = f.rel end
  local code, _, err = git_paths(s.root, { 'commit', '-m', WIP_SUBJECT, '--' }, paths)
  if code ~= 0 then
    return vim.notify('WorktreeReview: committing edits failed:\n' .. err, vim.log.levels.ERROR)
  end
  local e_sha = chomp(git_ok(s.root, { 'rev-parse', 'HEAD' }) or '')
  git(s.root, { 'update-ref', BACKUP_REF, e_sha })

  local _, wt_dirty = status_sets(s.wt_path)
  local was_dirty = next(wt_dirty) ~= nil
  -- insert E directly after the reviewed commit; the agent's later commits
  -- replay above it. --autostash: an in-flight agent does not block this.
  code, _, err = git(s.wt_path,
    { 'rebase', '--autostash', '--onto', e_sha, s.commit_wt_sha })

  if code == 0 then
    local restored = restore_main_to_base(s, e_sha)
    close_session()
    if not restored then return end
    local note = ('WorktreeReview: "%s" inserted after %s in %s — agent prompt copied to +')
      :format(WIP_SUBJECT, short(s.root, s.commit_wt_sha), s.wt_name)
    if #foreign > 0 then
      note = note .. '\n(left staged in main, not handed back: ' .. table.concat(foreign, ', ') .. ')'
    end
    deliver_agent_prompt(agent_prompt_success(s, e_sha))
    return vim.notify(note)
  end

  -- conflict (or failure): the worktree keeps the half-done rebase for the
  -- agent to finish; main still returns to base — E survives on BACKUP_REF
  local conflicted = vim.split(chomp(git_ok(s.wt_path,
    { 'diff', '--name-only', '--diff-filter=U' }) or ''), '\n')
  if #conflicted == 1 and conflicted[1] == '' then conflicted = {} end
  restore_main_to_base(s, e_sha)
  close_session()
  if #conflicted == 0 then
    return vim.notify(('WorktreeReview: handback rebase failed to start in %s:\n%s\n'
      .. 'My edits are safe: %s (ref %s). Retry or rebase manually with '
      .. '`git rebase --onto %s %s`'):format(s.wt_path, err, e_sha, BACKUP_REF, e_sha,
        s.commit_wt_sha), vim.log.levels.ERROR)
  end
  local prompt = agent_prompt_conflict(s, e_sha, conflicted, was_dirty)
  deliver_agent_prompt(prompt)
  show_prompt_buffer(prompt)
  vim.notify(('WorktreeReview: rebase stopped on conflicts in %s — left for the agent to '
    .. 'finish (prompt copied to + and opened). Main restored to %s; feedback kept on ref %s')
    :format(s.wt_name, short(s.root, s.base_sha), BACKUP_REF), vim.log.levels.WARN)
end

--------------------------------------------------------------------------------
-- <leader>gwc: commit my edits on main (AMEND or a message)
--------------------------------------------------------------------------------

local function apply_commit_choice(s, choice)
  local paths = {}
  for _, f in ipairs(s.files) do paths[#paths + 1] = f.rel end
  local code, out, err
  if choice == 'AMEND' then
    code, out, err = git_paths(s.root, { 'commit', '--amend', '--no-edit', '--' }, paths)
  else
    local msgfile = vim.fn.tempname()
    local f = assert(io.open(msgfile, 'w'))
    f:write(choice)
    f:close()
    code, out, err = git_paths(s.root, { 'commit', '-F', msgfile, '--' }, paths)
    os.remove(msgfile)
  end
  if code ~= 0 then
    return false, (err ~= '' and err or out)
  end
  return true
end

local function open_commit_prompt(s)
  local path = vim.fn.tempname()
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'gitcommit'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '# AMEND or a commit message below:',
    '',
  })
  -- capture the new window INSIDE the call: nvim_win_call restores the
  -- previous current window afterwards, so reading it outside grabs top_win
  local win
  vim.api.nvim_win_call(s.top_win, function()
    vim.cmd('rightbelow 8split ' .. vim.fn.fnameescape(path))
    win = vim.api.nvim_get_current_win()
  end)
  s.prompt_win, s.prompt_buf = win, buf
  vim.wo[win].winbar = 'commit review edits  ·  :w confirms · q cancels'
  vim.api.nvim_set_current_win(win)
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_call(win, function() vim.cmd('close') end)
  end, { buffer = buf, silent = true })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup, buffer = buf,
    callback = function()
      -- scheduled: wiping this buffer from inside its own BufWritePost is unsafe
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local kept = {}
        for _, l in ipairs(lines) do
          if not l:match('^%s*#') then kept[#kept + 1] = l end
        end
        local choice = vim.trim(table.concat(kept, '\n'))
        pcall(vim.api.nvim_win_call, win, function() vim.cmd('close') end) -- also wipes the buffer
        if choice == '' then return vim.notify('WorktreeReview: commit cancelled') end
        local ok, err = apply_commit_choice(s, choice)
        if not ok then
          return vim.notify('WorktreeReview: commit failed:\n' .. err, vim.log.levels.ERROR)
        end
        local subject = chomp(git_ok(s.root, { 'show', '-s', '--format=%s', 'HEAD' }) or '')
        close_session()
        if choice == 'AMEND' then
          -- a silent history rewrite deserves a visible receipt
          show_note_buffer('WorktreeReview-result', 'amended — your edits are in the pick',
            ('AMENDED the picked commit on main with your review edits:\n'
              .. '  %s -> %s   "%s"\n'
              .. 'No new commit was created — the pick itself was rewritten.\n'
              .. 'The worktree\'s own copy (%s) drops out once its branch is rebased onto %s:\n'
              .. 'git usually drops it as already-upstream; if that rebase stops on it, '
              .. '`git rebase --skip` it.'):format(short(s.root, s.commit_main_sha),
              short(s.root, 'HEAD'), subject, short(s.root, s.commit_wt_sha),
              upstream_branch(s.wt_path) or 'the upstream branch'))
          return vim.notify(('WorktreeReview: amended on main — "%s"'):format(subject))
        end
        vim.notify(('WorktreeReview: committed on main — "%s"'):format(subject))
      end)
    end,
  })
end

function M.commit_edits()
  local s = session
  if not s then return vim.notify('WorktreeReview: no review session open') end
  save_session_buffers(s)
  local edits, _ = session_edits(s)
  if #edits == 0 then return vim.notify('WorktreeReview: no edits to commit') end
  local head = chomp(git_ok(s.root, { 'rev-parse', 'HEAD' }) or '')
  if head ~= s.commit_main_sha then
    return vim.notify(('WorktreeReview: main HEAD moved to %s since the pick — resolve first')
      :format(short(s.root, head)), vim.log.levels.ERROR)
  end
  open_commit_prompt(s)
end

--------------------------------------------------------------------------------
-- abandon
--------------------------------------------------------------------------------

local function cancel_review()
  local s = session
  if not s then return end
  save_session_buffers(s)
  local head = chomp(git_ok(s.root, { 'rev-parse', 'HEAD' }) or '')
  if head ~= s.commit_main_sha then
    return vim.notify(('WorktreeReview: main HEAD moved to %s since the pick — cancel would '
      .. 'rewind past it; resolve first'):format(short(s.root, head)), vim.log.levels.ERROR)
  end
  local edits = session_edits(s)
  local e_sha
  if #edits > 0 then
    -- keep the discarded edits recoverable on the backup ref
    local paths = {}
    for _, f in ipairs(s.files) do paths[#paths + 1] = f.rel end
    local code, _, err = git_paths(s.root, { 'commit', '-m', WIP_SUBJECT, '--' }, paths)
    if code == 0 then
      e_sha = chomp(git_ok(s.root, { 'rev-parse', 'HEAD' }) or '')
      git(s.root, { 'update-ref', BACKUP_REF, e_sha })
    else
      vim.notify('WorktreeReview: could not snapshot edits:\n' .. err, vim.log.levels.WARN)
    end
  end
  local restored = restore_main_to_base(s, e_sha or s.commit_main_sha)
  close_session()
  if not restored then return end
  vim.notify(('WorktreeReview: cancelled — main restored to %s%s'):format(short(s.root, s.base_sha),
    e_sha and ('; edits kept on ref ' .. BACKUP_REF) or ''))
end

-- close on q / window close: with undispatched edits, ask what to do with them.
-- one prompt at a time — WinClosed and TabClosed can both fire for one close.
local prompting = false
local function prompted_close(from_window_close)
  local s = session
  if not s or prompting then return end
  save_session_buffers(s)
  local edits = session_edits(s)
  if #edits == 0 then return close_session() end
  prompting = true
  vim.ui.select(
    { 'Hand back as WIP (gf)', 'Keep on main & close', 'Discard & restore main' }, {
    prompt = 'Undispatched review edits:',
    format_item = function(l) return l end,
  }, function(choice)
    prompting = false
    -- Escape: leave everything as-is — the pick stays on main with any
    -- staged edits on top. Only exception: a pane/tab close triggered this
    -- prompt, the windows are going away, and a noop would strand a
    -- half-open session — finish the teardown, still git-neutral.
    if not choice then
      if from_window_close then
        close_session()
        vim.notify('WorktreeReview: edits stay on main (staged) — :WorktreeReviewCancel to discard')
      end
      return
    end
    if choice:find('^Hand back') then
      M.feedback()
    elseif choice:find('^Keep') then
      close_session()
      vim.notify('WorktreeReview: edits stay on main (staged) — commit them yourself or :WorktreeReviewCancel')
    else
      cancel_review()
    end
  end)
end

--------------------------------------------------------------------------------
-- picking
--------------------------------------------------------------------------------

local function next_sha(wt, branch)
  for _, s in ipairs(unupstreamed(wt, branch)) do
    if not picked[s] then return s end
  end
end

-- editable review files for a commit on main: its non-deleted, text files
local function review_files(root, base, commit)
  local out = git_ok(root, { 'diff-tree', '--no-renames', '-r', '--no-commit-id',
    '--name-status', '-z', base, commit }) or ''
  local fields = {}
  for f in out:gmatch('[^%z]+') do fields[#fields + 1] = f end
  local files = {}
  for i = 1, #fields, 2 do
    local status, rel = fields[i], fields[i + 1]
    local abs = root .. '/' .. rel
    if status ~= 'D' and vim.fn.filereadable(abs) == 1 and is_text(abs) then
      files[#files + 1] = { rel = rel, abs = abs }
    end
  end
  return files
end

local function open_review_tab(s)
  vim.cmd('tabnew')
  local junk = vim.api.nvim_get_current_buf()
  s.top_win = vim.api.nvim_get_current_win()

  -- bottom: read-only mirror of the top file at the pre-pick state
  vim.cmd('rightbelow split')
  s.old_win = vim.api.nvim_get_current_win()
  s.old_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[s.old_buf].buftype = 'nofile'
  vim.bo[s.old_buf].swapfile = false
  vim.bo[s.old_buf].bufhidden = 'hide'
  pcall(vim.api.nvim_buf_set_name, s.old_buf,
    ('WorktreeReview://%s'):format(short(s.root, s.commit_main_sha)))
  vim.api.nvim_win_set_buf(s.old_win, s.old_buf)

  -- top: the commit's files, editable; 1/3 bottom / 2/3 top
  if #s.files > 0 then
    local first = s.files[1]
    for _, f in ipairs(s.files) do
      f.buf = vim.fn.bufadd(f.abs)
      -- an unmodified buffer may still hold content from an older pick:
      -- force-read the just-cherry-picked state from disk
      pcall(vim.api.nvim_buf_call, f.buf, function() vim.cmd('silent! edit!') end)
      vim.bo[f.buf].bufhidden = 'hide'
      vim.bo[f.buf].buflisted = true
    end
    vim.api.nvim_win_set_buf(s.top_win, first.buf)
  else
    local empty = vim.api.nvim_create_buf(false, true)
    vim.bo[empty].buftype = 'nofile'
    vim.bo[empty].swapfile = false
    vim.bo[empty].modifiable = false
    vim.api.nvim_buf_set_lines(empty, 0, -1, false,
      { '[ nothing editable in this commit — see the mirror pane ]' })
    s.files = { { rel = '(none)', abs = '', buf = empty } }
    vim.api.nvim_win_set_buf(s.top_win, empty)
  end
  if vim.api.nvim_buf_is_valid(junk) and junk ~= s.files[1].buf and junk ~= s.old_buf then
    pcall(vim.cmd, 'bwipe ' .. junk)
  end

  -- 1/3 bottom mirror, 2/3 top editor
  local total = vim.api.nvim_win_get_height(s.top_win) + vim.api.nvim_win_get_height(s.old_win) + 1
  vim.api.nvim_win_set_height(s.old_win, math.max(1, math.floor(total / 3)))

  -- per-buffer keys: nav + dispatch from anywhere in the session
  local bufs = {}
  for _, f in ipairs(s.files) do bufs[#bufs + 1] = f.buf end
  bufs[#bufs + 1] = s.old_buf
  for _, b in ipairs(bufs) do
    local o = { buffer = b, silent = true }
    vim.keymap.set('n', '<leader>gwf', M.feedback, o)
    vim.keymap.set('n', '<leader>gwc', M.commit_edits, o)
    if #s.files > 1 then
      vim.keymap.set('n', '<leader>bn', next_file, o)
      vim.keymap.set('n', '<leader>bp', prev_file, o)
    end
  end
  vim.keymap.set('n', 'q', function() prompted_close() end, { buffer = s.old_buf, silent = true })

  vim.api.nvim_clear_autocmds({ group = augroup })
  for _, f in ipairs(s.files) do
    if f.abs ~= '' then
      -- :w persists the edit into the index — what was approved on screen is
      -- what gf/gC hand over
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = augroup, buffer = f.buf,
        callback = function(args) git(s.root, { 'add', '--', vim.api.nvim_buf_get_name(args.buf) }) end,
      })
      -- keep the diff pair in sync as the file is edited (vim will not
      -- recompute against a nofile partner on its own)
      vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
        group = augroup, buffer = f.buf,
        callback = function()
          repaint(s)
          vim.schedule(function() repaint(s) end)
        end,
      })
      vim.api.nvim_create_autocmd('TextChangedI', {
        group = augroup, buffer = f.buf,
        callback = function() repaint_debounced(s) end,
      })
    end
  end
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local win = tonumber(args.match)
      if session and (win == session.top_win or win == session.old_win) then prompted_close(true) end
    end,
  })
  vim.api.nvim_create_autocmd('TabClosed', {
    group = augroup,
    callback = function()
      if session and not vim.api.nvim_tabpage_is_valid(session.tab) then prompted_close(true) end
    end,
  })

  goto_index(1)
  s.tab = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_win(s.top_win)
end

local function pick_next(w)
  local branch = upstream_branch(w.path)
  if not branch then
    return vim.notify('WorktreeReview: no main/master branch found', vim.log.levels.ERROR)
  end
  local sha = next_sha(w.path, branch)
  if not sha then
    return vim.notify(('WorktreeReview: nothing ahead of %s in %s'):format(branch, w.path))
  end
  local root = main_root(w.path)

  local head = chomp(git_ok(root, { 'symbolic-ref', '--short', 'HEAD' }) or '')
  if head ~= branch then
    return vim.notify(('WorktreeReview: main worktree (%s) is on %s — switch it to %s first')
      :format(root, head ~= '' and head or 'a detached HEAD', branch), vim.log.levels.ERROR)
  end
  local staged, dirty = status_sets(root)
  if next(staged) then
    return vim.notify(('WorktreeReview: staged changes in %s — commit or unstage before picking')
      :format(root), vim.log.levels.ERROR)
  end
  local clash = {}
  for _, p in ipairs(commit_paths(w.path, sha)) do
    if dirty[p] then clash[#clash + 1] = p end
    -- a modified buffer for a file the commit touches would show stale pre-pick
    -- content; :w would silently autostage it and revert the pick
    local b = vim.fn.bufnr(root .. '/' .. p)
    if b ~= -1 and vim.bo[b].modified then
      clash[#clash + 1] = p .. ' (unsaved buffer ' .. b .. ')'
    end
  end
  if #clash > 0 then
    return vim.notify('WorktreeReview: these files are dirty or held in modified buffers — clean, stash or save first:\n  '
      .. table.concat(clash, '\n  '), vim.log.levels.ERROR)
  end

  local base_sha = chomp(git_ok(root, { 'rev-parse', 'HEAD' }) or '')
  local code, _, err = git(root, { 'cherry-pick', sha })
  if code ~= 0 then
    git(root, { 'cherry-pick', '--abort' })
    return vim.notify(('WorktreeReview: cherry-picking %s conflicted — rebase %s onto %s '
      .. 'first, then retry%s'):format(sha:sub(1, 7), w.path, branch,
        err ~= '' and '\n' .. err or ''), vim.log.levels.ERROR)
  end
  picked[sha] = true
  local s = {
    root = root,
    wt_path = w.path,
    wt_name = w.name,
    wt_branch = w.branch,
    base_sha = base_sha,
    commit_main_sha = chomp(git_ok(root, { 'rev-parse', 'HEAD' }) or ''),
    commit_wt_sha = sha,
    files = review_files(root, base_sha, 'HEAD'),
    index = 1,
  }
  set_session(s)
  open_review_tab(s)
  vim.notify(('WorktreeReview: reviewing %s ("%s") from %s')
    :format(short(root, s.commit_main_sha),
      chomp(git_ok(root, { 'show', '-s', '--format=%s', 'HEAD' }) or ''), w.name))
end

function M.start()
  local root = main_root(vim.uv.cwd())
  if not root then
    return vim.notify('WorktreeReview: not inside a git repository', vim.log.levels.ERROR)
  end
  local gs_ok, gitsplit = pcall(require, 'user.git')
  if gs_ok and gitsplit.session() then
    return vim.notify('WorktreeReview: close GitSplit first (both want the same buffers)',
      vim.log.levels.ERROR)
  end
  if session then
    save_session_buffers(session)
    if #session_edits(session) == 0 then
      close_session() -- clean session: replace it
    else
      prompted_close()
      return vim.notify('WorktreeReview: finish closing the open review, then <leader>gww again')
    end
  end
  local wts = {}
  for _, w in ipairs(worktrees(root)) do
    local label = 'worktrees/' .. w.name .. '/'
    local branch = upstream_branch(w.path)
    if branch then label = label .. '  ·  ' .. ahead_behind(w.path, branch) end
    if git_ok(w.path, { 'status', '--porcelain' }) ~= '' then label = label .. '  ·  dirty' end
    wts[#wts + 1] = { path = w.path, label = label, name = w.name, branch = w.branch }
  end
  if #wts == 0 then
    return vim.notify('WorktreeReview: no worktrees under ' .. root .. '/worktrees/')
  end

  vim.ui.select(wts, {
    prompt = 'Worktree to review:',
    format_item = function(w) return w.label end,
  }, function(w)
    if w then pick_next(w) end
  end)
end

M.cancel = cancel_review

-- exposed for tests / scripting
M.session = function() return session end
M.close = close_session
M.prompted_close = prompted_close
M.next_file = next_file
M.prev_file = prev_file

vim.api.nvim_create_user_command('WorktreeReview', function() M.start() end, {})
vim.api.nvim_create_user_command('WorktreeReviewCancel', function() cancel_review() end, {})
vim.api.nvim_create_user_command('WorktreeReviewFeedbackSubmission', function() M.feedback() end, {})
vim.api.nvim_create_user_command('WorktreeReviewCommit', function() M.commit_edits() end, {})
vim.keymap.set('n', '<leader>gww', M.start,
  { desc = 'WorktreeReview: pick the next worktree commit into main' })

return M
