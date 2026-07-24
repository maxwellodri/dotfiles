-- GitSplit: open a fugitive-style vertical diff (HEAD on the left, working
-- tree on the right) for every dirty / untracked file in the repo, in a fresh
-- dedicated tab.
--
--   :GitSplit        (also bound to nothing by default -- see bottom)
--
-- Behaviour:
--   * "Git tree is clean" + early no-op if nothing is dirty/untracked.
--   * LHS = HEAD version of the file; RHS = the working-tree file (editable).
--   * Untracked / brand-new files have an empty LHS with a virtual banner, so
--     the whole file reads as added.
--   * Binary files are skipped; vim.g.GitSplitIgnore (default {}) lists
--     repo-relative files/directories to always skip as well.
--   * <leader>bn / <leader>bp / <leader>bd work from EITHER pane and keep both
--     in sync: there is one shared "current file" index, and advancing it
--     updates both panes together. `bd` drops the current file and moves on.
--   * `q` (LHS pane only, so the RHS keeps macro recording) closes the session
--     (the tab); working-tree buffers are left in the buffer list for editing.

local M = {}

local ns = vim.api.nvim_create_namespace('user.git.gitsplit')
local augroup = vim.api.nvim_create_augroup('user.git.gitsplit', { clear = true })
local state = nil -- populated by M.open, cleared by M.close

-- Default: ignore nothing. Override per-project, e.g. in an exrc:
--   vim.g.GitSplitIgnore = { './notes/', 'build/' }
-- Entries are repo-relative files OR directories (leading `./` and trailing `/`
-- are stripped). A file is skipped if it equals an entry or lives beneath one.
vim.g.GitSplitIgnore = vim.g.GitSplitIgnore or {}

-- the three nav keys bound on every session buffer (LHS + RHS). `q` is bound
-- only on the LHS pane, so it is not part of this set.
local SESSION_KEYS = { '<leader>bn', '<leader>bp', '<leader>bd' }

local function clear_buf_keymaps(b)
  if not vim.api.nvim_buf_is_valid(b) then return end
  for _, k in ipairs(SESSION_KEYS) do
    pcall(vim.keymap.del, 'n', k, { buffer = b })
  end
end

--------------------------------------------------------------------------------
-- git helpers
--------------------------------------------------------------------------------

local function git_root()
  local out = vim.fn.systemlist({ 'git', 'rev-parse', '--show-toplevel' })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then return nil end
  return out[1]
end

-- Heuristic: a file counts as "text" if its first chunk has no NUL byte --
-- the same rule vim and git use. Binary files (images, .fbx/.pdf/.png assets,
-- build artifacts, ...) are useless in a vim diff and they also trip bigfile
-- plugins, so we skip them outright.
local function is_text(path)
  local f = io.open(path, 'rb')
  if not f then return false end
  local chunk = f:read(8192) or ''
  f:close()
  return chunk:find('\0', 1, true) == nil
end

-- True if `rel` (a path relative to the repo root) is covered by a
-- vim.g.GitSplitIgnore entry (a file or directory). Accepts a string or list.
local function ignored(rel)
  local v = vim.g.GitSplitIgnore
  local list = type(v) == 'string' and { v } or (type(v) == 'table' and v or {})
  for _, entry in ipairs(list) do
    local e = entry:gsub('^%./', ''):gsub('/$', '')
    if e ~= '' and (rel == e or rel:sub(1, #e + 1) == e .. '/') then
      return true
    end
  end
  return false
end

-- Collect dirty + untracked files. We use `-z` (raw, unquoted paths -- plain
-- porcelain v1 would C-quote any path containing spaces / non-ASCII and silently
-- drop it) with `--no-renames`, so every record is exactly `XY path<NUL>`.
-- Deletions are dropped (no working copy to display) and binary / non-text files
-- are skipped (a binary diff is meaningless and would trip bigfile plugins).
local function collect_files(root)
  local res = vim.system({ 'git', '-C', root, 'status', '--porcelain=v1',
    '--untracked-files=all', '-z', '--no-renames' }):wait()
  local raw = (res and res.code == 0 and res.stdout) or ''
  local files = {}
  for entry in raw:gmatch('[^%z]+') do
    if #entry >= 3 then
      local x, y = entry:sub(1, 1), entry:sub(2, 2)
      if x ~= 'D' and y ~= 'D' then
        local path = entry:sub(4)
        local abs = root .. '/' .. path
        if vim.fn.filereadable(abs) == 1 and is_text(abs) and not ignored(path) then
          table.insert(files, { rel = path, abs = abs, untracked = (x == '?' and y == '?') })
        end
      end
    end
  end
  return files
end

-- Lines of HEAD:<rel> (CRLF normalized to LF so they line up with the RHS,
-- which Neovim reads with dos fileformat), or nil if not in HEAD yet.
local function head_lines(root, rel)
  local out = vim.fn.systemlist({ 'git', '-C', root, 'show', 'HEAD:' .. rel })
  if vim.v.shell_error ~= 0 then return nil end
  for i, line in ipairs(out) do
    out[i] = line:gsub('\r$', '')
  end
  return out
end

--------------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------------

-- Fill the shared left scratch buffer with the HEAD version of `file`, or leave
-- it empty with a virtual banner for untracked / brand-new files. `ft` is the
-- on-screen file's filetype, used to light up the LHS.
local function set_lhs_content(buf, root, file, ft)
  vim.bo[buf].modifiable = true
  local banner
  if file.untracked then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    banner = '[ untracked file — no committed version in HEAD ]'
  else
    local lines = head_lines(root, file.rel)
    if lines then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    else
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      banner = '[ new file — staged but not present in HEAD ]'
    end
  end
  vim.bo[buf].modifiable = false

  -- We set `syntax` (NOT `filetype`): setting filetype would re-fire FileType
  -- autocmds -- e.g. vimtex / bigfile -- on this throwaway nofile buffer on every
  -- file switch. Syntax alone gives regex highlighting cheaply.
  vim.bo[buf].syntax = ft or ''

  -- (re)draw the untracked banner as a non-diff virtual line
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if banner then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_lines = { { { banner, 'WarningMsg' } } },
      virt_lines_above = true,
      priority = 200,
    })
  end
end

local function refresh()
  if not state then return end
  local file = state.files[state.index]
  if not file then return end

  local rhs = state.rhs_bufs[state.index]
  if vim.api.nvim_win_is_valid(state.rhs_win) and vim.api.nvim_buf_is_valid(rhs) then
    vim.api.nvim_win_set_buf(state.rhs_win, rhs)
  end

  -- match LHS highlighting to the now-loaded RHS file (fallback to filename)
  local ft = (vim.api.nvim_buf_is_valid(rhs) and vim.bo[rhs].filetype) or ''
  if ft == '' then ft = vim.filetype.match({ filename = file.abs }) or '' end
  set_lhs_content(state.lhs_buf, state.root, file, ft)

  for _, w in ipairs({ state.lhs_win, state.rhs_win }) do
    if vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_call(w, function() vim.cmd('diffthis') end)
    end
  end
  vim.cmd('diffupdate')

  if vim.api.nvim_win_is_valid(state.lhs_win) then
    vim.wo[state.lhs_win].winbar = '[HEAD] ' .. file.rel .. (file.untracked and '  (untracked)' or '')
  end
  if vim.api.nvim_win_is_valid(state.rhs_win) then
    vim.wo[state.rhs_win].winbar = ('[WORK] %s  (%d/%d)'):format(file.rel, state.index, #state.files)
  end
end

--------------------------------------------------------------------------------
-- navigation (shared by both panes -- there's one linked file index)
--------------------------------------------------------------------------------

local function goto_index(i)
  if not state or #state.files == 0 then return end
  state.index = ((i - 1) % #state.files) + 1
  refresh()
end

local function next_file() goto_index((state and state.index or 1) + 1) end
local function prev_file() goto_index((state and state.index or 1) - 1) end

-- Called (deferred) when a working-tree buffer is deleted by any means, so even
-- a raw `:bd` stays in sync.
local function on_rhs_deleted(bufnr)
  if not state then return end
  clear_buf_keymaps(bufnr) -- the buffer may persist (e.g. after a raw :bd); drop its nav keys
  for i, b in ipairs(state.rhs_bufs) do
    if b == bufnr then
      table.remove(state.files, i)
      table.remove(state.rhs_bufs, i)
      if i < state.index then
        state.index = state.index - 1 -- an earlier file vanished; keep the viewed one stable
      end
      break
    end
  end
  if #state.files == 0 then
    return vim.schedule(M.close)
  end
  if state.index > #state.files then state.index = #state.files end
  refresh()
end

local function delete_current()
  if not state then return end
  local i = state.index
  local b = state.rhs_bufs[i]
  if not b or not vim.api.nvim_buf_is_valid(b) then return end

  local suffix = ' ' .. b
  if vim.bo[b].modified then
    local choice = vim.fn.confirm(
      ('GitSplit: %s has unsaved changes. Discard?'):format(state.files[i].rel),
      '&Discard\n&Cancel', 2)
    if choice ~= 1 then return end
    suffix = '! ' .. b
  end

  -- drop from session state first, then refresh the RHS onto the next file so
  -- the buffer we're deleting is no longer displayed (clean delete, no window
  -- churn). The BufDelete autocmd no-ops for it (already removed from state).
  table.remove(state.files, i)
  table.remove(state.rhs_bufs, i)

  if #state.files == 0 then
    M.close()                          -- closes the tab; working buffers left as-is
    pcall(vim.cmd, 'bdelete' .. suffix)
    return
  end

  if state.index > #state.files then state.index = #state.files end
  refresh()
  pcall(vim.cmd, 'bdelete' .. suffix)
end

-- exposed for scripting / :lua require('user.git').next_file()
M.next_file = next_file
M.prev_file = prev_file
M.delete_current = delete_current

--------------------------------------------------------------------------------
-- session lifecycle
--------------------------------------------------------------------------------

local function session_keymaps(b)
  local o = { buffer = b, silent = true }
  vim.keymap.set('n', '<leader>bn', next_file, o)
  vim.keymap.set('n', '<leader>bp', prev_file, o)
  vim.keymap.set('n', '<leader>bd', delete_current, o)
end

local function clear_rhs_keymaps(s)
  for _, b in ipairs(s.rhs_bufs) do clear_buf_keymaps(b) end
end

function M.close()
  local s = state
  if not s then return end
  state = nil

  for _, w in ipairs({ s.lhs_win, s.rhs_win }) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_call, w, function() vim.cmd('diffoff') end)
    end
  end
  clear_rhs_keymaps(s)

  if vim.api.nvim_tabpage_is_valid(s.tab) then
    pcall(vim.cmd, 'tabclose ' .. vim.api.nvim_tabpage_get_number(s.tab))
  end
  if vim.api.nvim_buf_is_valid(s.lhs_buf) then
    pcall(vim.cmd, 'bwipe ' .. s.lhs_buf)
  end
  vim.api.nvim_clear_autocmds({ group = augroup })
end

function M.open()
  if state then M.close() end

  local root = git_root()
  if not root then
    return vim.notify('GitSplit: not inside a git repository', vim.log.levels.ERROR)
  end

  local files = collect_files(root)
  if #files == 0 then
    return vim.notify('Git tree is clean', vim.log.levels.INFO)
  end

  -- shared left pane (HEAD version), a nofile scratch we rewrite per file
  local lhs_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[lhs_buf].buftype = 'nofile'
  vim.bo[lhs_buf].bufhidden = 'hide'
  vim.bo[lhs_buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, lhs_buf, 'GitSplit://HEAD')

  -- one real working-tree buffer per file (so :ls / :bn / :bd / edits all work).
  -- NOTE: we only bufadd() (listed, cyclable) -- we do NOT bufload() up front.
  -- FileType plugins (vimtex, bigfile, ...) therefore only attach to the file
  -- currently on screen, not to every dirty file at once. The buffer is loaded
  -- lazily when refresh() displays it in the RHS window.
  local rhs_bufs = {}
  for _, f in ipairs(files) do
    local b = vim.fn.bufadd(f.abs)
    vim.bo[b].bufhidden = 'hide'
    vim.bo[b].buflisted = true -- bufadd() leaves buffers unlisted in Neovim; force it for :ls / :bn / telescope
    table.insert(rhs_bufs, b)
  end

  -- fresh dedicated tab; LHS on the left, RHS on the right (no global option churn)
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
    root = root,
    files = files,
    rhs_bufs = rhs_bufs,
    lhs_buf = lhs_buf,
    lhs_win = lhs_win,
    rhs_win = rhs_win,
    index = 1,
    tab = vim.api.nvim_get_current_tabpage(),
  }

  -- reset any stale autocmds from a previous session, then wire this one
  vim.api.nvim_clear_autocmds({ group = augroup })
  session_keymaps(lhs_buf)
  for _, b in ipairs(rhs_bufs) do
    session_keymaps(b)
    vim.api.nvim_create_autocmd('BufDelete', {
      group = augroup, buffer = b,
      callback = function() vim.schedule(function() on_rhs_deleted(b) end) end,
    })
  end
  -- `q` to quit lives only on the (non-editable) LHS so the RHS keeps macro
  -- recording (`q{reg}`) available.
  vim.keymap.set('n', 'q', M.close, { buffer = lhs_buf, silent = true })
  -- if the user closes our tab directly, tear the session down cleanly
  vim.api.nvim_create_autocmd('TabClosed', {
    group = augroup,
    callback = function()
      if state and not vim.api.nvim_tabpage_is_valid(state.tab) then M.close() end
    end,
  })

  refresh()
  if vim.api.nvim_win_is_valid(rhs_win) then
    vim.api.nvim_set_current_win(rhs_win)
  end
end

vim.api.nvim_create_user_command('GitSplit', function() M.open() end, {})

-- No default keybind: `<leader>g*` is crowded in this config. Map it yourself,
-- e.g.:
--   vim.keymap.set('n', '<leader>gs', require('user.git').open,
--     { desc = 'GitSplit: HEAD vs working diff for all dirty files' })

return M
