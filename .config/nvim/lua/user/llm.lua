local M = {}

function M.cmd_to_clip()
  vim.cmd 'normal! gv"vy'
  local lines = vim.fn.getreg 'v'
  if #lines == 0 then return end

  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)

  if path:sub(1, #vim.env.HOME) == vim.env.HOME then
    path = '~' .. path:sub(#vim.env.HOME + 1)
  end

  local cmd = string.format('cat %s', vim.fn.shellescape(path))
  vim.fn.setreg('+', cmd)
  vim.notify('Copied: ' .. cmd, vim.log.levels.INFO)
end
function M.setup()
  vim.keymap.set('v', '<leader>ac', require('buffer_to_clip').cmd_to_clip, { desc = 'Copy buffer-cat cmd' })
end

return M
