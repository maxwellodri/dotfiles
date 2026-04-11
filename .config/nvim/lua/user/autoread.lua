vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  command = "silent! checktime",
})

local timer = vim.loop.new_timer()
timer:start(1000, 1000, vim.schedule_wrap(function()
  vim.cmd('silent! checktime')
end))

