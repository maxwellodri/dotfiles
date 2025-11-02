vim.g.suda_smart_edit = 1
vim.api.nvim_create_autocmd("User", {
  pattern = "SudaWrite",
  callback = function()
    print("Saved with sudo!")
  end,
})

