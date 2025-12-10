local M = {}
M.open_workspace_toml = function()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 then
    vim.notify("Not in a git repository")
    return
  end

  local cargo_toml = git_root .. '/Cargo.toml'
  if vim.fn.filereadable(cargo_toml) == 1 then
    vim.cmd('edit ' .. vim.fn.fnameescape(cargo_toml))
  else
    vim.notify("Can't find workspace Cargo.toml")
  end
end
M.setup = function(opts)
  -- positionEncodings = { "utf-16", "utf-8" } --TODO integrate by extending opts.capabilities.general
  local config = vim.lsp.config['rust_analyzer']
  vim.lsp.config['rust_analyzer'] = vim.tbl_deep_extend('force', config or {}, {
    cmd = { 'rust-analyzer' },
    root_markers = { 'Cargo.toml', 'rust-project.json' },
    filetypes = { 'rust' },
    capabilities = opts.capabilities,
    on_attach = function(client, bufnr)
      opts.on_attach(client, bufnr)
      vim.diagnostic.enable(true, { bufnr = bufnr })
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

      local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
      end
      map("n", "gd", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
        clients[1]:request('textDocument/definition', params, function(err, result)
          if err or not result or vim.tbl_isempty(result) then
            vim.print("Definition not found")
            return
          end
          vim.cmd('silent! w')
          vim.cmd('vsplit')
          vim.lsp.util.show_document(result[1], clients[1].offset_encoding)
        end, bufnr)
      end, "Go to definition in vsplit")

      map("n", "gi", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
        clients[1]:request('textDocument/definition', params, function(err, result)
          if err or not result or vim.tbl_isempty(result) then
            vim.print("Definition not found")
            return
          end
          vim.cmd('silent! w')
          vim.lsp.util.show_document(result[1], clients[1].offset_encoding)
        end, bufnr)
      end, "Go to definition")
      map("n", "<leader>M", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
        clients[1]:request('rust-analyzer/expandMacro', params, function(err, result)
          if err then
            vim.notify("Expand macro failed: " .. vim.inspect(err), vim.log.levels.ERROR)
          elseif result and result.expansion then
            vim.cmd('vsplit')
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_win_set_buf(0, buf)
            local lines = vim.split(result.expansion, '\n')
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].filetype = 'rust'
            vim.bo[buf].buftype = 'nofile'
            vim.bo[buf].bufhidden = 'wipe'
          else
            vim.notify("Cursor not on a macro")
          end
        end, bufnr)
      end, "Expand Macro")

      map("v", "J", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local start_line = vim.fn.line('v') - 1
        local end_line = vim.fn.line('.') - 1
        local min_line = math.min(start_line, end_line)
        local max_line = math.max(start_line, end_line)

        local params = {
          textDocument = vim.lsp.util.make_text_document_params(bufnr),
          ranges = {{
            start = { line = min_line, character = 0 },
            ["end"] = { line = max_line + 1, character = 0 }
          }}
        }

        clients[1]:request('experimental/joinLines', params, function(err, result)
          if err then
            vim.notify("Join lines failed: " .. vim.inspect(err), vim.log.levels.ERROR)
          elseif result then
            vim.lsp.util.apply_text_edits(result, bufnr, clients[1].offset_encoding)
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
            vim.api.nvim_win_set_cursor(0, {min_line + 1, 0})
            vim.cmd('normal! ^')
          end
        end, bufnr)
      end, "Join Lines")
      map("n", "<leader>gk", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
        clients[1]:request('experimental/parentModule', params, function(err, result)
          if err then
            vim.notify("Parent module failed: " .. vim.inspect(err), vim.log.levels.ERROR)
          elseif result and result[1] then
            vim.lsp.util.show_document(result[1], clients[1].offset_encoding)
          end
        end, bufnr)
      end, "Open Parent Module")

      map("n", "<leader>gb", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
        clients[1]:request('experimental/externalDocs', params, function(err, result)
          if err then
            vim.notify("External docs failed: " .. vim.inspect(err), vim.log.levels.ERROR)
          elseif result then
            local url = result.uri or result.url or result
            require('user.languages.rust.open_docs').ModifyOpenDocsUrl(url)
          end
        end, bufnr)
      end, "Open Documentation")

      map("n", "<leader>gt", function()
        local clients = vim.lsp.get_clients({bufnr = bufnr, name = 'rust_analyzer'})
        if not clients[1] then return end

        local params = {
          textDocument = vim.lsp.util.make_text_document_params()
        }
        clients[1]:request('experimental/openCargoToml', params, function(err, result)
          if err then
            vim.notify("Open Cargo.toml failed: " .. vim.inspect(err), vim.log.levels.ERROR)
          elseif result then
            vim.lsp.util.show_document(result, clients[1].offset_encoding)
          end
        end, bufnr)
      end, "Open Cargo.toml")

      map("n", "<leader>gT", M.open_workspace_toml, "Open Workspace Cargo.toml")

      map("n", "<leader>rM", function()
        vim.notify("Restarting rust-analyzer")
        vim.lsp.stop_client(vim.lsp.get_clients({ name = "rust_analyzer" }))
        vim.defer_fn(function()
          vim.cmd('edit')
        end, 500)
      end, "Restart rust-analyzer")
    end,
    settings = {
      ['rust-analyzer'] = {
        diagnostics = { enable = false },
        checkOnSave = { enable = false },
        cargo = {
          allFeatures = true,
          loadOutDirsFromCheck = true,
          buildScripts = { enable = true },
        },
        procMacro = {
          enable = true,
          attributes = { enable = true }
        },
        imports = { prefix = "crate" },
        inlayHints = {
          bindingModeHints = { enable = false },
          chainingHints = { enable = true },
          closingBraceHints = { enable = true, minLines = 30 },
          closureReturnTypeHints = { enable = "with_block" },
          lifetimeElisionHints = { enable = "skip_trivial" },
          parameterHints = { enable = false },
          reborrowHints = { enable = "never" },
          typeHints = { enable = false },
        },
      },
    },
  })
  vim.lsp.enable("rust_analyzer")
  vim.lsp.config['bacon_ls'] = {
    cmd = { 'bacon-ls' },
    root_markers = { 'Cargo.toml' },
    filetypes = { 'rust' },
    capabilities = opts.capabilities,
    on_init = function(client)
      client.server_capabilities.codeActionProvider = false
    end,
    on_attach = opts.on_attach,
    init_options = {
      updateOnSave = true,
      updateOnSaveWaitMillis = 100,
    }
  }
  vim.lsp.enable("bacon_ls")
end

return M
