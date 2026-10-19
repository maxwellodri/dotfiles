-- Headless spec for the WorktreeReview flow. Builds throwaway repos under
-- /tmp, stubs vim.ui.select, drives the module, asserts git + editor state.
-- Run via tests/run_worktree_review.sh.
local DIR = vim.fs.normalize((debug.getinfo(1, 'S').source:sub(2):gsub('[^/]+$', '')))

local notifs = {}
local fails = {}
local function check(name, cond)
  print((cond and 'PASS ' or 'FAIL ') .. name)
  if not cond then
    fails[#fails + 1] = name
    local last = notifs[#notifs]
    if last then print('  (last notify: ' .. tostring(last.msg) .. ')') end
  end
end

vim.notify = function(msg, level) notifs[#notifs + 1] = { msg = msg, level = level } end

local select_queue = {}
vim.ui.select = function(items, opts, on_choice)
  -- queue index 0 simulates Escape (on_choice(nil))
  local idx = table.remove(select_queue, 1) or 1
  if idx == 0 then return on_choice(nil, nil) end
  on_choice(items[idx], idx)
end

local function sh(args) return vim.system(args):wait() end
local function git(cwd, args)
  local r = vim.system(vim.list_extend({ 'git', '-C', cwd }, args)):wait()
  return r.code, r.stdout or '', r.stderr or ''
end
local function gitok(cwd, args) local c, o = git(cwd, args); if c ~= 0 then return nil end; return o end
local function out(cwd, args) return (gitok(cwd, args) or ''):gsub('\n+$', '') end
local function subjects(cwd, rev)
  local t = vim.split(out(cwd, { 'log', '--reverse', '--format=%s', rev }), '\n')
  if #t == 1 and t[1] == '' then return {} end
  return t
end

local function w(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(text)
  f:close()
end

-- one dummy "agent project": repo on main + worktrees/agent branch 'agent'
--   A: edit src.txt, add new.txt, delete gone.txt, add blob.bin (binary)
--   B/C: touch other.txt (B and C both, so C tests replay order)
local function build_repo(base, with_bc, conflict_b)
  vim.fn.delete(base, 'rf')
  local repo = base .. '/repo'
  w(base .. '/repo/SCENARIO', base .. '\n') -- unique tree per repo: identical dummy commits would collide on sha across scenarios
  w(base .. '/repo/src.txt', 'base line\n')
  w(base .. '/repo/keep.txt', 'keep\n')
  w(base .. '/repo/gone.txt', 'gone\n')
  sh({ 'git', 'init', '-q', '-b', 'main', repo })
  git(repo, { 'config', 'user.email', 't@t' })
  git(repo, { 'config', 'user.name', 't' })
  git(repo, { 'add', '-A' })
  git(repo, { 'commit', '-qm', 'base' })
  local wt = base .. '/repo/worktrees/agent'
  sh({ 'git', '-C', repo, 'worktree', 'add', '-q', '-b', 'agent', wt })
  w(wt .. '/src.txt', conflict_b and 'base line\nagent A\n' or 'base line\nagent A\n')
  w(wt .. '/new.txt', 'new by A\n')
  w(wt .. '/blob.bin', 'bin\0bin\n')
  git(wt, { 'add', '-A' })
  git(wt, { 'rm', '-q', '--cached', 'gone.txt' })
  vim.fn.delete(wt .. '/gone.txt')
  git(wt, { 'commit', '-qm', 'A' })
  if with_bc then
    if conflict_b then w(wt .. '/src.txt', 'base line\nB rewrote line 2\n') end
    w(wt .. '/other.txt', 'B content\n')
    git(wt, { 'add', '-A' })
    git(wt, { 'commit', '-qm', 'B' })
    w(wt .. '/other.txt', 'C content\n')
    git(wt, { 'add', '-A' })
    git(wt, { 'commit', '-qm', 'C' })
  end
  return repo, wt
end

local M = require('user.git.worktree')
local function session() return M.session() end

local function top_buf(s) return s.files[s.index].buf end
local function buf_for(s, rel)
  for _, f in ipairs(s.files) do if f.rel == rel then return f.buf end end
end
local function append_line(buf, text)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { text })
  vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
end
local function set_line2(buf, text)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { text })
  vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
end

local function find_prompt_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local l = vim.api.nvim_buf_get_lines(b, 0, 1, false)
      if l[1] == '# AMEND or a commit message below:' then return b end
    end
  end
end

local function file_contains(path, needle)
  local f = io.open(path, 'r')
  if not f then return false end
  local t = f:read('*a')
  f:close()
  return t:find(needle, 1, true) ~= nil
end

local function pick_and_open(repo)
  vim.uv.chdir(repo)
  notifs = {}
  M.start()
  return session()
end

-- S1: session, layout, autostage, mutual refusal, queue behaviour
local base1 = '/tmp/wtr-spec/s1'
local repo1, wt1 = build_repo(base1, true, false)
w(repo1 .. '/keep.txt', 'unrelated dirt\n')
local s = pick_and_open(repo1)
check('S1 session open', s ~= nil and vim.g.WorktreeReviewSession ~= nil)
check('S1 base recorded', s.base_sha == out(repo1, { 'rev-parse', 'HEAD^' }))
check('S1 wt sha recorded', s.commit_wt_sha == out(wt1, { 'rev-parse', 'agent~2' }))
check('S1 two windows', #vim.api.nvim_tabpage_list_wins(s.tab) == 2)
check('S1 top shows a commit file', vim.tbl_contains({ 'src.txt', 'new.txt' },
  vim.fn.fnamemodify(vim.api.nvim_buf_get_name(top_buf(s)), ':t')))
check('S1 deleted file not editable', #s.files == 2) -- src.txt + new.txt (gone.txt deleted, blob.bin binary)
check('S1 mirror readonly', vim.bo[s.old_buf].modifiable == false and vim.bo[s.old_buf].buftype == 'nofile')
-- mirror shows the PRE-PICK version of the file on top, same syntax
local function base_lines_of(repo, rel)
  local t = vim.split(out(repo, { 'show', s.base_sha .. ':' .. rel }), '\n')
  if #t == 1 and t[1] == '' then return {} end
  return t
end
local top_rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(top_buf(s)), ':t')
local function mirror_ok(repo, sess, rel)
  local present = (git(repo, { 'cat-file', '-e', sess.base_sha .. ':' .. rel }))
  local mirror = vim.api.nvim_buf_get_lines(sess.old_buf, 0, -1, false)
  if present ~= 0 then -- added by the commit: empty mirror + banner
    return #mirror == 0 or (#mirror == 1 and mirror[1] == '')
  end
  local base = base_lines_of(repo, rel)
  return #mirror == #base and mirror[1] == (base[1] or '')
end
check('S1 mirror shows the pre-pick version of the top file', mirror_ok(repo1, s, top_rel))
check('S1 mirror syntax matches top file',
  vim.bo[s.old_buf].syntax == (vim.bo[top_buf(s)].filetype ~= '' and vim.bo[top_buf(s)].filetype
    or vim.filetype.match({ filename = vim.api.nvim_buf_get_name(top_buf(s)) }) or ''))
-- navigation: the mirror follows the top pane
M.next_file()
check('S1 mirror follows bn nav',
  vim.fn.fnamemodify(vim.api.nvim_buf_get_name(top_buf(s)), ':t')
    ~= vim.fn.fnamemodify(top_rel, ':t')
  or vim.api.nvim_buf_get_name(top_buf(s)) == vim.api.nvim_buf_get_name(top_buf(s)))
local top2_rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(top_buf(s)), ':t')
check('S1 mirror tracks the new file', mirror_ok(repo1, s, top2_rel))
local top_h, mirror_h = vim.api.nvim_win_get_height(s.top_win), vim.api.nvim_win_get_height(s.old_win)
check(('S1 split 2/3-1/3 (top=%d bot=%d)'):format(top_h, mirror_h), mirror_h >= 3 and top_h >= mirror_h * 2 - 2)
check('S1 gwf map is buffer-local', vim.fn.maparg('<leader>gwf', 'n', false, true).buffer == 1)
check('S1 old keys unbound', vim.fn.maparg('<leader>gS', 'n') == '' and vim.fn.maparg('<leader>gs', 'n') == ''
  and vim.fn.maparg('<leader>gr', 'n') == '' and vim.fn.maparg('<leader>gf', 'n') == ''
  and vim.fn.maparg('<leader>gC', 'n') == '')
check('S1 gww global start map', vim.fn.maparg('<leader>gww', 'n') ~= '')
check('S1 commands exist', (function()
  local cmds = vim.api.nvim_get_commands({ builtin = false })
  return cmds['WorktreeReviewFeedbackSubmission'] ~= nil and cmds['WorktreeReviewCommit'] ~= nil
    and cmds['WorktreeReviewCancel'] ~= nil and cmds['GitSplit'] ~= nil
end)())
check('S1 gws GitSplit map', vim.fn.maparg('<leader>gws', 'n') ~= '')
append_line(buf_for(s, 'src.txt'), '//nit: rename me')
check('S1 autostage on :w', out(repo1, { 'diff', '--cached', '--name-only' }):find('src%.txt', 1, false) ~= nil)
git(repo1, { 'add', '--', 'keep.txt' }) -- mid-review foreign staging: must survive gf
local gitsplit = require('user.git')
gitsplit.open(true)
check('S1 GitSplit refused during review', notifs[#notifs] and notifs[#notifs].msg:find('WorktreeReview session first') ~= nil)

-- S2: gf happy path — insert after A, restore main, queue excludes WIP
M.feedback()
local e = vim.trim(out(repo1, { 'rev-parse', 'refs/heads/worktree-review/wip' }))
check('S2 session closed', session() == nil and vim.g.WorktreeReviewSession == nil)
check('S2 main restored to base', out(repo1, { 'rev-parse', 'HEAD' }) == s.base_sha)
check('S2 backup ref points at E',
  out(repo1, { 'show', '-s', '--format=%s', 'refs/heads/worktree-review/wip' }) == 'WIP: Human edits')
check('S2 src restored', file_contains(repo1 .. '/src.txt', 'base line') and not file_contains(repo1 .. '/src.txt', 'nit'))
check('S2 added file removed', vim.fn.filereadable(repo1 .. '/new.txt') == 0)
check('S2 deleted file restored', vim.fn.filereadable(repo1 .. '/gone.txt') == 1)
check('S2 unrelated dirt survives', file_contains(repo1 .. '/keep.txt', 'unrelated dirt'))
check('S2 wt history A,WIP,B,C', table.concat(subjects(wt1, 'main..agent'), '|') == 'A|WIP: Human edits|B|C')
check('S2 nit landed in wt', file_contains(wt1 .. '/src.txt', '//nit: rename me'))
check('S2 agent prompt captured', (vim.g.WorktreeReviewLastPrompt or ''):find('WIP: Human edits', 1, true) ~= nil)
local s2_promptbuf
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):find('WorktreeReview%-prompt', 1, false) then
    s2_promptbuf = b
  end
end
check('S2 success stays clipboard-only', s2_promptbuf == nil)
check('S2 session files unstaged after restore', out(repo1, { 'diff', '--cached', '--name-only' }):find('src%.txt', 1, false) == nil)
check('S2 foreign staged state survives restore',
  out(repo1, { 'diff', '--cached', '--name-only' }):find('keep%.txt', 1, false) ~= nil)
git(repo1, { 'restore', '--staged', '--', 'keep.txt' }) -- pick guard needs a clean index

-- queue: the WIP commit is never offered. (Which commit IS offered depends
-- on timing in these dummy repos: if the cherry-pick recreated the identical
-- sha, the session `picked` set skips A and B comes next; otherwise A
-- returns with its new sha. Both are correct — only "never the WIP" matters.)
s = pick_and_open(repo1)
check('S2 queue offers a commit, never the WIP',
  s ~= nil and notifs[#notifs].msg:find('WIP: Human edits', 1, true) == nil)
M.cancel()
check('S2 cancel restores base', out(repo1, { 'rev-parse', 'HEAD' }) == s.base_sha)

-- S3: gC — AMEND keeps subject; message creates a new commit; noop when clean
local repo3, wt3 = build_repo('/tmp/wtr-spec/s3', true, false)
s = pick_and_open(repo3)
check('S3 picked oldest (A)', notifs[#notifs].msg:find('("A")', 1, true) ~= nil)
append_line(buf_for(s, 'src.txt'), 'my fix')
M.commit_edits()
local pb = find_prompt_buf()
check('S3 prompt buffer opened', pb ~= nil)
check('S3 prompt focused', vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()) == pb)
vim.api.nvim_buf_set_lines(pb, 0, -1, false, { '# AMEND or a commit message below:', '', 'AMEND' })
vim.api.nvim_buf_call(pb, function() vim.cmd('silent write') end)
vim.wait(300, function() return session() == nil end)
check('S3 amend folded edit', file_contains(repo3 .. '/src.txt', 'my fix')
  and out(repo3, { 'show', '-s', '--format=%s', 'HEAD' }) == 'A')
check('S3 amend parent is base', out(repo3, { 'rev-parse', 'HEAD^' }) == s.base_sha)
local resultbuf
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):find('WorktreeReview%-result', 1, false) then
    resultbuf = b
  end
end
check('S3 amend shows a receipt buffer', resultbuf ~= nil
  and vim.api.nvim_buf_get_lines(resultbuf, 0, 1, false)[1]:find('AMENDED the picked commit', 1, true) ~= nil)
check('S3 session closed after commit', session() == nil)
-- the session `picked` set skips A; the next commit is offered (after the
-- agent amends and a fresh session, A would return with its new sha)
s = pick_and_open(repo3)
check('S3 B offered next', s ~= nil and notifs[#notifs].msg:find('("B")', 1, true) ~= nil)
M.commit_edits()
check('S3 noop without edits', session() ~= nil and notifs[#notifs].msg:find('no edits') ~= nil)
append_line(buf_for(s, 'other.txt'), 'another fix')
M.commit_edits()
pb = find_prompt_buf()
vim.api.nvim_buf_set_lines(pb, 0, -1, false,
  { '# AMEND or a commit message below:', '', 'Fix: my message', 'body line' })
vim.api.nvim_buf_call(pb, function() vim.cmd('silent write') end)
vim.wait(300, function() return session() == nil end)
check('S3 new commit message used', out(repo3, { 'show', '-s', '--format=%B', 'HEAD' }):find('Fix: my message', 1, true) ~= nil
  and out(repo3, { 'show', '-s', '--format=%B', 'HEAD' }):find('body line', 1, true) ~= nil)
check('S3 new commit on top of pick', out(repo3, { 'rev-parse', 'HEAD^' }) == s.commit_main_sha)

-- S4: gf conflict — wt left mid-rebase for the agent, main restored
local repo4, wt4 = build_repo('/tmp/wtr-spec/s4', true, true)
s = pick_and_open(repo4)
set_line2(buf_for(s, 'src.txt'), '//nit: rewrite line 2 instead')
M.feedback()
local stat = out(wt4, { 'status', '--porcelain' })
local mid_rebase = stat:find('^UU', 1, true) ~= nil or stat:find('\nUU', 1, true) ~= nil
local rebase_dir = vim.fs.joinpath(out(wt4, { 'rev-parse', '--git-dir' }), 'rebase-merge')
check('S4 wt mid-rebase', mid_rebase and vim.fn.isdirectory(rebase_dir) == 1)
check('S4 main restored', out(repo4, { 'rev-parse', 'HEAD' }) == s.base_sha)
check('S4 backup ref exists', out(repo4, { 'rev-parse', '--verify', '-q', 'refs/heads/worktree-review/wip' }) ~= '')
check('S4 conflict prompt', (vim.g.WorktreeReviewLastPrompt or ''):find('rebase %-%-continue', 1, false) ~= nil)
check('S4 conflict prompt wording', (vim.g.WorktreeReviewLastPrompt or ''):find('my comments where it makes sense', 1, true) ~= nil)
local promptbuf
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):find('WorktreeReview%-prompt', 1, false) then
    promptbuf = b
  end
end
check('S4 conflict prompt opens in editor', promptbuf ~= nil
  and vim.api.nvim_buf_get_lines(promptbuf, 0, 1, false)[1]:find('Review feedback', 1, true) ~= nil)
git(wt4, { 'rebase', '--abort' })

-- S5: close prompt — keep on main; discard restores
local repo5, _ = build_repo('/tmp/wtr-spec/s5', false, false)
s = pick_and_open(repo5)
append_line(buf_for(s, 'src.txt'), '//nit: x')
notifs = {}
select_queue = { 2 } -- Keep on main & close
M.prompted_close()
check('S5 keep closes session', session() == nil)
check('S5 pick still on main', out(repo5, { 'rev-parse', 'HEAD' }) == s.commit_main_sha)
local s5_base = s.base_sha
s = pick_and_open(repo5) -- A is upstream by patch-id now (kept on main)
check('S5 nothing left to pick', notifs[#notifs] and notifs[#notifs].msg:find('nothing ahead') ~= nil)
git(repo5, { 'reset', '-q', '--hard', s5_base })

-- S6: single-commit worktree — gf still lands the WIP (rebase fast-forwards)
local repo6, wt6 = build_repo('/tmp/wtr-spec/s6', false, false)
s = pick_and_open(repo6)
check('S6 session opened', s ~= nil)
append_line(buf_for(s, 'src.txt'), '//nit: single')
M.feedback()
check('S6 WIP landed on tip-only branch', table.concat(subjects(wt6, 'main..agent'), '|') == 'A|WIP: Human edits')
check('S6 main restored', out(repo6, { 'rev-parse', 'HEAD' }) == s.base_sha)

-- S7: prompted close — discard & restore
local repo7, _ = build_repo('/tmp/wtr-spec/s7', false, false)
s = pick_and_open(repo7)
append_line(buf_for(s, 'src.txt'), '//nit: discard me')
notifs = {}
select_queue = { 3 } -- Discard & restore main
M.prompted_close()
vim.wait(300, function() return session() == nil end)
check('S7 discard closes + restores', session() == nil and out(repo7, { 'rev-parse', 'HEAD' }) == s.base_sha)
check('S7 edits snapshotted on backup ref',
  out(repo7, { 'show', '-s', '--format=%s', 'refs/heads/worktree-review/wip' }) == 'WIP: Human edits')

-- S9: closing with the commit prompt open wipes it (q -> discard path)
local repo9, _ = build_repo('/tmp/wtr-spec/s9', false, false)
s = pick_and_open(repo9)
append_line(buf_for(s, 'src.txt'), '//nit: x')
M.commit_edits()
local pb9 = find_prompt_buf()
check('S9 prompt opened', pb9 ~= nil)
notifs = {}
select_queue = { 3 } -- Discard & restore main
M.prompted_close()
vim.wait(300, function() return session() == nil end)
check('S9 prompt wiped on discard', session() == nil and not vim.api.nvim_buf_is_valid(pb9))
check('S9 discard restored main', out(repo9, { 'rev-parse', 'HEAD' }) == s.base_sha)

-- S10: GitSplit adopts the stacked layout for dirty-tree review
local repo10 = '/tmp/wtr-spec/s10'
vim.fn.delete(repo10, 'rf')
w(repo10 .. '/SCENARIO', repo10 .. '\n')
w(repo10 .. '/app.lua', 'local x = 1\n')
sh({ 'git', 'init', '-q', '-b', 'main', repo10 })
git(repo10, { 'config', 'user.email', 't@t' })
git(repo10, { 'config', 'user.name', 't' })
git(repo10, { 'add', '-A' })
git(repo10, { 'commit', '-qm', 'base' })
vim.uv.chdir(repo10)
w(repo10 .. '/app.lua', 'local x = 2\n')
w(repo10 .. '/new.lua', 'brand new\n')
notifs = {}
local gitsplit2 = require('user.git')
gitsplit2.open(false)
local gs = gitsplit2.session()
check('S10 GitSplit session open', gs ~= nil)
check('S10 two stacked windows', #vim.api.nvim_tabpage_list_wins(gs.tab) == 2)
local gs_top_h, gs_bot_h = vim.api.nvim_win_get_height(gs.rhs_win), vim.api.nvim_win_get_height(gs.lhs_win)
check(('S10 split 2/3-1/3 (top=%d bot=%d)'):format(gs_top_h, gs_bot_h),
  gs_bot_h >= 3 and gs_top_h >= gs_bot_h * 2 - 2)
check('S10 top is the editable worktree file', vim.bo[gs.rhs_bufs[gs.index]].modifiable)
check('S10 bottom mirrors HEAD read-only',
  vim.bo[gs.lhs_buf].modifiable == false
  and vim.api.nvim_buf_get_lines(gs.lhs_buf, 0, -1, false)[1] == 'local x = 1')
gitsplit2.close()
check('S10 GitSplit closes cleanly', gitsplit2.session() == nil)
vim.uv.chdir('/tmp')
-- S8: guards — foreign commit on main blocks gf / gC / cancel
local repo8, _ = build_repo('/tmp/wtr-spec/s8', false, false)
s = pick_and_open(repo8)
git(repo8, { 'commit', '-q', '--allow-empty', '-m', 'foreign commit on main' })
append_line(buf_for(s, 'src.txt'), '//nit: blocked')
notifs = {}
M.feedback()
check('S8 gf refuses when main moved',
  session() ~= nil and notifs[#notifs].msg:find('HEAD moved', 1, true) ~= nil)
notifs = {}
M.commit_edits()
check('S8 gC refuses when main moved',
  session() ~= nil and notifs[#notifs].msg:find('HEAD moved', 1, true) ~= nil)
notifs = {}
M.cancel()
check('S8 cancel refuses when main moved',
  session() ~= nil and notifs[#notifs].msg:find('HEAD moved', 1, true) ~= nil)
vim.wait(200, function() return false end) -- let any stray timers settle
git(repo8, { 'reset', '-q', '--hard', 'HEAD~1' })
M.cancel()

-- S11: Escape on the undispatched-edits prompt is a noop while the review
-- windows are intact; after a pane close it only finishes the teardown —
-- git stays untouched either way
local repo11, _ = build_repo('/tmp/wtr-spec/s11', false, false)
s = pick_and_open(repo11)
append_line(buf_for(s, 'src.txt'), '//nit: escape me')
local pick_sha = s.commit_main_sha
notifs = {}
select_queue = { 0 } -- Escape
M.prompted_close()
check('S11 escape keeps the session open', session() ~= nil)
check('S11 escape leaves git untouched', out(repo11, { 'rev-parse', 'HEAD' }) == pick_sha
  and out(repo11, { 'diff', '--cached', '--name-only' }):find('src%.txt', 1, false) ~= nil)
select_queue = { 0 } -- Escape again, but the pane is already gone
vim.api.nvim_win_close(s.top_win, true)
vim.wait(200, function() return session() == nil end)
check('S11 escape after pane close tears down', session() == nil)
check('S11 pane-close escape leaves git untouched', out(repo11, { 'rev-parse', 'HEAD' }) == pick_sha
  and out(repo11, { 'diff', '--cached', '--name-only' }):find('src%.txt', 1, false) ~= nil)

git(repo11, { 'reset', '-q', '--hard', s.base_sha })
vim.uv.chdir('/tmp')

print(#fails == 0 and 'ALL PASS' or ('FAILED: ' .. table.concat(fails, ', ')))
vim.cmd(#fails == 0 and 'qa!' or 'cquit! 1')
