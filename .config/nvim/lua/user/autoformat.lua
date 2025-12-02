vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  pattern = { "*" },
  callback = function()
    if vim.bo.filetype ~= "rust" then
      vim.cmd([[%s/\s\+$//e]])
    end
  end,
})
