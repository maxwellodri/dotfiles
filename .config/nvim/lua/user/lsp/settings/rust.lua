local M = {}
M.setup = function (opts)
  -- Autoformat Rust files on save using rustfmt
  -- vim.api.nvim_create_autocmd("BufWritePre", {
  --   pattern = "*.rs",
  --   callback = function()
  --     -- Save cursor position before formatting
  --     local cursor_pos = vim.api.nvim_win_get_cursor(0)
  --     -- Run rustfmt on the current buffer
  --     vim.cmd('%!rustfmt 2>/dev/null >/dev/null')
  --     -- Restore cursor position after formatting
  --     vim.api.nvim_win_set_cursor(0, cursor_pos)
  --   end
  -- })
  vim.g.rustaceanvim = {
    tools = {
      open_url = function(url)
        -- Run the script with the URL as an argument in a detached process
        vim.fn.jobstart({
          "_rust-analyzer-url_handler",
          url
        }, {
            detach = true  -- Run in the background
          })
      end,
    },
    dap = {},
    server = {
      config = opts.config,
      capabilities = opts.capabilities,
      on_attach = function(client, bufnr)
        vim.fn.system("mkdir -p /tmp/rust-analyzer-check")
        vim.diagnostic.enable(bufnr)
        opts.on_attach(client, bufnr)

        vim.keymap.set("n", "<leader>M", function() vim.cmd("RustLsp expandMacro") end, { silent = true, desc = "Expand Macro" })
        vim.keymap.set("n", "J", function() vim.cmd("RustLsp joinLines") end, { silent = true, desc = "Join Lines" })
        vim.keymap.set("n", "<leader>gk", function() vim.cmd("RustLsp parentModule") end, { silent = true, desc = "Open Parent Module" })
        vim.keymap.set("n", "<leader>gb", function() vim.cmd("RustLsp openDocs") end, { silent = true, desc = "Open Documentation" })
        vim.keymap.set("n", "<leader>gt", function() vim.cmd("RustLsp openCargo") end, { silent = true, desc = "Open Cargo.toml" })
      end,
      handlers = {
        --vim.notify_once("Rust LSP ready to go")
      },
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
            extraArgs={"--target-dir", "/tmp/rust-analyzer-check"},
            allTargets = false,
            runBuildScripts = false,
          },
          cargo = {
            loadOutDirsFromCheck = true,
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
        }
      }
    },
  }
end
return M
