require("user.lsp.handlers").setup()
local opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}

local lspconfig = require'lspconfig'
local rust_opts = require("user.lsp.settings.rust")
require'lspconfig'.gdscript.setup{
  on_attach = opts.on_attach,
  capabilities = opts.capabilities,
  config = opts.config,
}

require("mason-lspconfig").setup_handlers({
  function (server_name)
    lspconfig[server_name].setup {
      on_attach = opts.on_attach,
      capabilities = opts.capabilities,
      config = opts.config,
          }
      end,
      ["rust_analyzer"] = function ()
        require('rust-tools').setup(rust_opts)
      end,
})
