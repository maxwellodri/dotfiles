if not vim.g.reloading_config then--snacks needs to be setup early (other plugins depend on it - :checkhealth snacks), snacks doesnt like being reloaded
    require("snacks").setup({
      bigfile = { enabled = true },
      quickfile = { enabled = true },
    })
end
