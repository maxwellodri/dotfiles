vim.opt.viewoptions = "folds,cursor,curdir"
vim.opt.foldenable = true
vim.opt.foldmethod = "manual"
vim.opt.viewdir = vim.fn.stdpath("data") .. "/view"

vim.api.nvim_create_autocmd({"BufWinLeave"}, {
  pattern = {"*.*"},
  desc = "save view (folds), when closing file only if a view already exists",
  callback = function()
    local view_file = vim.fn.stdpath("data") .. "/view/" .. vim.fn.expand("%:p"):gsub("/", "="):gsub("=", "%%") .. "="
    if vim.fn.filereadable(view_file) == 1 then
      vim.cmd("mkview")
    end
  end
})
vim.api.nvim_create_autocmd({"BufWinEnter"}, {
  pattern = {"*.*"},
  desc = "load view (folds), when opening file",
  command = "silent! loadview"
})
