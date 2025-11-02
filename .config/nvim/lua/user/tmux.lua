vim.api.nvim_create_autocmd("BufWritePost", {
  callback = function()
    if vim.bo.filetype == "tmux" then
      local config_home = vim.fn.expand("$XDG_CONFIG_HOME")
      if config_home == "" then
        config_home = vim.fn.expand("$HOME") .. "/.config"
      end
      vim.fn.system("tmux source-file " .. config_home .. "/tmux/tmux.conf")
      vim.cmd('silent! redraw | echo "Reloaded tmux.conf"')
    end
  end,
})
