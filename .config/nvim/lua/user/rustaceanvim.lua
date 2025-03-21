local rust_opts = require("user.lsp.settings.rust")
local default_opts = require('user.lsp')

for _, method in ipairs({ 'textDocument/diagnostic', 'workspace/diagnostic' }) do
  local default_diagnostic_handler = vim.lsp.handlers[method]
  vim.lsp.handlers[method] = function(err, result, context, config)
    -- Ignore ServerCancelled error globally
    if err and err.code == -32802 then
      return
    end
    return default_diagnostic_handler(err, result, context, config)
  end
end

vim.g.rustfmt_autosave = 0 --use LSP instead
vim.g.rustaceanvim = {
  -- Plugin configuration
  tools = {
    on_initialized = function()
      vim.print("Rust LSP ready to go...")
    end,
    reload_workspace_from_cargo_toml = true
  },
  -- LSP configuration
  server = {
    on_attach = function(client, bufnr)
      -- vim.diagnostic.disable(bufnr)
      default_opts.on_attach(client, bufnr)
      -- vim.api.nvim_create_autocmd("BufWritePre", {
      --   buffer = bufnr,
      --   callback = function()
      --     vim.lsp.buf.format({ async = false })
      --   end,
      -- })

      vim.keymap.set("n","<leader>gc", function() vim.cmd.RustLsp('codeAction') end, { silent = true, buffer = bufnr })
      vim.keymap.set("n","<leader>gk", function() vim.cmd.RustLsp('parentModule') end, { silent = true })
      vim.keymap.set("n","<leader>gd", function() vim.cmd.RustLsp('debuggables') end, { silent = true})
      vim.keymap.set("n","<leader>gb", function() vim.cmd.RustLsp('openDocs') end, { silent = true })
      vim.keymap.set("n","<leader>gt", function() vim.cmd.RustLsp('openCargo') end, { silent = true })
      vim.keymap.set("n","<leader>M", function() vim.cmd.RustLsp('expandMacro') end, { silent = true })
      vim.keymap.set("n","<leader>gr", function() vim.cmd.RustLsp('runnables') end, { silent = true })
    end,
    config = default_opts.capabilities,
    capabilities = default_opts.capabilities,
    default_settings = {
      ["rust-analyzer"] = {
        diagnostics = { enabled = true, disabled = {"inactive-code", "unlinked-file"} },
        semanticHighlighting = {
          enabled = true,
        },
        procMacro = {
          enable = true,
          attributes = {
            enable = true,
          }
        },
        checkOnSave = {
          command = "clippy",
          extraArgs={"--target-dir", "/var/tmp/rust-analyzer-check"},
          allTargets = false,
          runBuildScripts = false,
        },
        cargo = {
          loadOutDirsFromCheck = true,
        },
        imports = { prefix = "crate" },
        inlay_hints = {
          lifetimeElisionHints = { enable = "skip_trivial" },
          only_current_line_autocmd = "CursorHold",
          show_parameter_hints = true,
          -- prefix for parameter hints
          parameter_hints_prefix = "", -- <- ",
          -- prefix for all the other hints (type, chaining)
          other_hints_prefix = "=> ",
          -- whether to align to the length of the longest line in the file
          max_len_align = true,
          -- padding from the left if max_len_align is true
          max_len_align_padding = 4,
          -- whether to align to the extreme right or not
          right_align = false,
          -- padding from the right if right_align is true
          right_align_padding = 8,
          -- The color of the hints
          highlight = "SpecialComment",
        },

      }
    },
  },
  dap = {},
}
