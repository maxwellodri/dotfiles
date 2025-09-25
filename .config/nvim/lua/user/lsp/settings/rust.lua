M = {}
M.setup = function(opts)
  vim.g.rustaceanvim = {
    dap = {},
    server = {
    config = opts.config,
    capabilities = opts.capabilities,
       on_attach = function(client, bufnr)
         vim.diagnostic.enable(bufnr)
         opts.on_attach(client, bufnr)
         vim.keymap.set("n", "<leader>M", function() vim.cmd("RustLsp expandMacro") end, { silent = true, desc = "Expand Macro" })
         vim.keymap.set("n", "J", function() vim.cmd("RustLsp joinLines") end, { silent = true, desc = "Join Lines" })
         vim.keymap.set("n", "<leader>gk", function() vim.cmd("RustLsp parentModule") end, { silent = true, desc = "Open Parent Module" })
         vim.keymap.set("n", "<leader>gb", function() vim.cmd("RustLsp openDocs") end, { silent = true, desc = "Open Documentation" })
         vim.keymap.set("n", "<leader>gt", function() vim.cmd("RustLsp openCargo") end, { silent = true, desc = "Open Cargo.toml" })
       end,
      default_settings = {
        ['rust-analyzer'] = {
          -- Enable diagnostics
          diagnostics = { enabled = true, disabled = {"inactive-code", "unlinked-file"} },
          checkOnSave = true,
          check = {
            command = "clippy",
          },
          cargo = {
            allFeatures = true,
            loadOutDirsFromCheck = true,
            buildScripts = { enable = true },
          },
          procMacro = {
             enable = true,
             attributes = {
               enable = true,
             }
           },
           imports = { prefix = "crate" },
           inlay_hints = {
             enable = true,
             lifetimeElisionHints = { enable = "skip_trivial" },
             only_current_line_autocmd = "CursorHold",
             show_parameter_hints = true,
             parameter_hints_prefix = "",
             other_hints_prefix = "=> ",
             max_len_align = true,
             max_len_align_padding = 4,
             right_align = false,
             right_align_padding = 8,
             highlight = "SpecialComment",
           },
        },
      },
    },
  }
end
return M
