vim.opt.autoread = true
local timer = vim.loop.new_timer()
timer:start(200, 200, vim.schedule_wrap(function()
  vim.cmd('checktime')
end))

