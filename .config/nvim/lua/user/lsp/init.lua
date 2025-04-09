require("user.lsp.handlers").setup()
vim.lsp.set_log_level("ERROR")
Opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}
local lspconfig = require'lspconfig'

require("mason-lspconfig").setup_handlers({
  function (server_name)
    lspconfig[server_name].setup {
      on_attach = Opts.on_attach,
      capabilities = Opts.capabilities,
      config = Opts.config,
    }
  end,
  ["rust_analyzer"] = function ()
    --
  end,
})


function GoNextIssue()
  -- Check if there are any errors in the buffer
  local all_errors = vim.diagnostic.get(nil, {
    severity = vim.diagnostic.severity.ERROR,
  })

  if #all_errors > 0 then
    -- Navigate to the next error if present
    vim.diagnostic.goto_next({
      severity = vim.diagnostic.severity.ERROR,
      float = false  -- Disable the popup box
    })
  else
    -- Check if there are any non-error diagnostics (warnings, etc.)
    local all_other_diagnostics = vim.diagnostic.get(nil, {
      severity = {
        vim.diagnostic.severity.WARN,
        vim.diagnostic.severity.INFO,
        vim.diagnostic.severity.HINT,
      },
    })

    if #all_other_diagnostics > 0 then
      vim.notify("No errors found, reverting to warnings", vim.log.levels.INFO)
      vim.diagnostic.goto_next({
        severity = {
          vim.diagnostic.severity.WARN,
          vim.diagnostic.severity.INFO,
          vim.diagnostic.severity.HINT,
        },
        float = false  -- Disable the popup box
      })
    else
      vim.notify("No more valid diagnostics to move to", vim.log.levels.INFO)
    end
  end
end

vim.api.nvim_set_keymap('n', '<leader>ge', '<cmd>lua GoNextIssue()<CR>', { noremap = true, silent = true })

local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', '6014')
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
