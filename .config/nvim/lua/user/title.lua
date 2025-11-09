vim.opt.title = true

vim.api.nvim_create_autocmd({"BufEnter", "DirChanged"}, {
  callback = function()
    local git_dir = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
    if vim.v.shell_error == 0 then
      vim.opt.titlestring = "vim " .. vim.fn.fnamemodify(git_dir, ":t")
    else
      vim.opt.titlestring = "vim " .. vim.fn.expand("%:t")
    end
  end
})
