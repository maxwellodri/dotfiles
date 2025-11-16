local keymap_group = vim.api.nvim_create_augroup('TomlKeymaps', { clear = true })
M = {}
M.setup = function(opts)
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'toml',
    group = keymap_group,
    desc = 'Set keymap for TOML files',
    callback = function(args)
      local bufnr = args.buf
      local open_workspace_toml = require('user.languages.rust').open_workspace_toml
      vim.keymap.set('n', '<leader>gT', open_workspace_toml, {
        buffer = bufnr,
        silent = true,
        desc = 'Open Workspace Cargo.toml'
      })
    end,
  })
  require("crates").setup {
    lsp = {
      enabled = true,
      on_attach =  opts.on_attach,
      actions = true,
      completion = true,
      hover = true,
    },
  }
end
return M
