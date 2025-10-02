vim.lsp.set_log_level("ERROR")
require("user.lsp.handlers").setup()
Opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}
require('user.lsp.settings.rust').setup(Opts)
local lspconfig = require'lspconfig'
local mason = require('user.lsp.mason')
mason.setup()
for _, server in ipairs(mason.get_auto_enable_servers()) do
  lspconfig[server].setup {
    on_attach = Opts.on_attach,
    capabilities = Opts.capabilities,
    config = Opts.config,
  }
end

function GoNextIssue()
  local all_diagnostics = vim.diagnostic.get(nil)
  
  if #all_diagnostics == 0 then
    vim.notify("No diagnostics found", vim.log.levels.INFO)
    return
  end
  
    local current_buf = vim.api.nvim_get_current_buf()
  local all_errors = vim.diagnostic.get(current_buf, {
    severity = vim.diagnostic.severity.ERROR,
  })
  
   if #all_errors > 0 then
     pcall(vim.diagnostic.goto_next, {
       severity = vim.diagnostic.severity.ERROR,
       float = false,
       wrap = true
     })
   else
     pcall(vim.diagnostic.goto_next, {
       float = false,
       wrap = true
     })
   end
end

vim.api.nvim_set_keymap('n', '<leader>ge', '<cmd>lua GoNextIssue()<CR>', { noremap = true, silent = true })

local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', 6014)
require('lspconfig').gdscript.setup{ cmd = godot_cmd, on_attach = Opts.on_attach, flags = { debounce_text_changes = 150, } }
require("crates").setup {
  lsp = {
    enabled = true,
    on_attach =  Opts.on_attach,
    actions = true,
    completion = true,
    hover = true,
  },
  --null_ls = {
  --  enabled = true,
  --  name = "crates.nvim",
  --},
}
return Opts
