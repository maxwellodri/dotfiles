local M = {}
local function wait_for_diagnostics_then_init()
  if M.initialized then return end
  
  -- Set up a timer to check for diagnostics
  local timer_count = 0
  local check_timer = vim.loop.new_timer()
  
  check_timer:start(500, 500, vim.schedule_wrap(function()
    -- Debug information
    vim.print("Check #" .. timer_count .. " for diagnostics")
    
    -- Check if diagnostics exist for any rust files
    local has_diagnostics = false
    local rust_buffers_found = false
    
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        local ok, ft = pcall(vim.api.nvim_buf_get_option, bufnr, "filetype")
        
        if ok and ft == "rust" then
          rust_buffers_found = true
          local diags = vim.diagnostic.get(bufnr)
          vim.print("Rust buffer " .. bufnr .. " has " .. #diags .. " diagnostics")
          
          if #diags > 0 then
            has_diagnostics = true
            break
          end
        end
      end
    end
    
    if not rust_buffers_found then
      vim.print("No Rust buffers found")
    end
    
    -- Check for active rust_analyzer client
    local has_rust_client = false
    local clients = vim.lsp.get_active_clients()
    for _, client in ipairs(clients) do
      if client.name == "rust_analyzer" then
        has_rust_client = true
        vim.print("rust_analyzer client is active")
        break
      end
    end
    
    if not has_rust_client then
      vim.print("No active rust_analyzer client found")
    end
    
    timer_count = timer_count + 1
    if has_diagnostics then
      check_timer:stop()
      M.initialized = true
      vim.print("Rust LSP ready to go with diagnostics")
    elseif timer_count > 10 and not M.initialized then
      check_timer:stop()
      M.initialized = true
      vim.print("Warning: Rust LSP taking a long time to initialize. Proceeding anyway...")
    end
  end))
end
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


function M.setup(opts)
  return {
    wait_for_diagnostics_then_init = wait_for_diagnostics_then_init,
    on_attach = function(client, bufnr)
      vim.diagnostic.enable(bufnr)
      opts.on_attach(client, bufnr)
      vim.keymap.set("n","<leader>H", rust_lsp_debug, { silent = true, desc = "Debug Rust LSP Status" })
    end,
    config = opts.config,
    capabilities = opts.capabilities,
    settings = {
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
    },
  }
end

return M
