require("user.lsp.handlers").setup()
vim.lsp.set_log_level("TRACE")
local opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}

local lspconfig = require'lspconfig'
local rust_opts = require("user.lsp.settings.rust")

local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', '6012')
require('lspconfig').gdscript.setup{ cmd = godot_cmd, on_attach = opts.on_attach, flags = { debounce_text_changes = 150, } }










-- cmd = vim.lsp.connect("127.0.0.1", 6005) -- godot

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
