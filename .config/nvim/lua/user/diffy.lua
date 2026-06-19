local diffy = require('diffy')

diffy.setup({
  width = 0.9,
  height = 0.85,
  border = 'rounded',
  winblend = 0,
})

local function staged_state(file)
  local dir = vim.fn.fnamemodify(file, ':p:h')
  local st = vim.fn.systemlist({ 'git', '-C', dir, 'status', '--porcelain=v1', '--', file })
  if vim.v.shell_error ~= 0 then return 'notgit' end
  if st[1] and st[1]:sub(1, 2) == '??' then return 'untracked' end
  vim.fn.system({ 'git', '-C', dir, 'diff', '--cached', '--quiet', '--', file })
  return vim.v.shell_error == 0 and 'none' or 'has'
end

local function open_staged()
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then
    return vim.notify('diffy: no file in the current buffer', vim.log.levels.WARN)
  end
  local rel = vim.fn.fnamemodify(file, ':.')
  local state = staged_state(file)
  if state == 'untracked' then
    return vim.notify(("diffy: `%s` is new and not staged yet — `:Git add %s`, then `<leader>gd`."):format(rel, rel), vim.log.levels.WARN)
  end
  if state == 'none' then
    return vim.notify(("diffy: no staged changes for `%s` (try `:Diffy` for unstaged)."):format(rel), vim.log.levels.INFO)
  end
  diffy.open_diff('staged')
end

vim.keymap.set('n', '<leader>gd', open_staged,
  { desc = 'Diffy: staged (git diff --cached)' })
