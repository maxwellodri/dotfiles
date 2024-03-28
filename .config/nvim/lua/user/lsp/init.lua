require("user.lsp.handlers").setup()
vim.lsp.set_log_level("TRACE")
local opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}

local lspconfig = require'lspconfig'
local rust_opts = require("user.lsp.settings.rust")

 -- require'lspconfig'.gdscript.setup({
 --   on_attach = opts.on_attach,
 --   capabilities = opts.capabilities,
 --   settings = opts.settings,
 --   cmd = {"websocat", "ws://127.0.0.1:6005", "--jsonrpc"},
 -- })
--
local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', '6011')
-- local godot_server_pipe = os.getenv("HOME") .. "/.cache/nvim/godot-server.pipe"
require('lspconfig').gdscript.setup{ cmd = godot_cmd, on_attach = opts.on_attach, flags = { debounce_text_changes = 150, } }
-- -- on_attach = opts.on_attach, 










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
