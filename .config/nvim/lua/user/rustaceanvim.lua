local rust_opts = require("user.lsp.settings.rust")
local default_opts = require('user.lsp')

vim.g.rustaceanvim = {
  -- Plugin configuration
  tools = {
    on_initialized = function() vim.print("Rust Lsp ready to go...") end,
    reload_workspace_from_cargo_toml = true
  },
  -- LSP configuration
  server = {
    on_attach = function(client, bufnr)
      default_opts.on_attach(client, bufnr)
      --client.offset_encoding = "utf-8"
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
        diagnostics = { enabled = true, disabled = {"inactive-code"} },
 			  procMacro = {
 			    enable = true,
 			    attributes = {
 			      enable = true,
 			    }
 			  },
 			  checkOnSave = {
 			  	command = "clippy",
          extraArgs={"--target-dir", "/var/tmp/rust-analyzer-check"}
 			  },
 			  -- cargo = {
 			  -- 	loadOutDirsFromCheck = true,
 			  -- },
        imports = { prefix = "crate" },
        inlay_hints = { lifetimeElisionHints = { enable = "skip_trivial" }, },
      }
    },
  },
  dap = {},
}
