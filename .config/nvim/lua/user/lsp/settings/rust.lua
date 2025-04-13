local M = {}
local rust_lsp_debug = function()
  local clients = vim.lsp.get_active_clients({ bufnr = 0 })
  local output = {}
  if #clients > 0 then
    local rust_client = nil
    for _, client in ipairs(clients) do
      if client.name == "rust_analyzer" then
        rust_client = client
        break
      end
    end
    if rust_client then
      table.insert(output, "Rust LSP status:")
      table.insert(output, "  • Client name: " .. rust_client.name)
      table.insert(output, "  • Client ID: " .. rust_client.id)
      table.insert(output, "  • Server capabilities: ")
      table.insert(output, "    - Diagnostics provider: " .. tostring(rust_client.server_capabilities.diagnosticProvider ~= nil))
      table.insert(output, "    - Code actions: " .. tostring(rust_client.server_capabilities.codeActionProvider ~= nil))
      table.insert(output, "  • Diagnostics count: " .. #vim.diagnostic.get(0))
      table.insert(output, "LSP is properly connected and running!")
    else
      table.insert(output, "No rust_analyzer client attached to current buffer")
    end
  else
    table.insert(output, "No LSP clients attached to current buffer")
  end
  -- Create a floating window
  local width = 60
  local height = #output
  local buf = vim.api.nvim_create_buf(false, true)
  -- Calculate position (centered)
  local ui = vim.api.nvim_list_uis()[1]
  local win_width = ui.width
  local win_height = ui.height
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)
  -- Set buffer contents
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  -- Create window
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = "Rust LSP Debug Info",
    title_pos = "center"
  }
  local win = vim.api.nvim_open_win(buf, true, win_opts)
  -- Add keymapping to close the window with q or ESC
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':close<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':close<CR>', { noremap = true, silent = true })

  -- Highlight the buffer content
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NormalFloat')
end

M.setup = function (opts)
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

        vim.keymap.set("n","<leader>H", rust_lsp_debug, { silent = true, desc = "Debug Rust LSP Status" })
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
