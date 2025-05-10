local M = {}

-- TODO: backfill this to template
M.setup = function()
  local function goto_definition(split_cmd)
    local util = vim.lsp.util
    local log = require("vim.lsp.log")
    local handler = function(_, result, ctx)
      if result == nil or vim.tbl_isempty(result) then
        local _ = log.info() and log.info(ctx.method, "No location found")
        return nil
      end
      local client_id = ctx.client_id
      local client = vim.lsp.get_client_by_id(client_id)
      local offset_encoding = client and client.offset_encoding or "utf-8"  -- Fallback to 'utf-8' if not available
      if split_cmd then
        vim.cmd(split_cmd)
      end
      if vim.tbl_islist(result) then
        -- Just jump to the first result and don't open the quickfix list
        util.jump_to_location(result[1], offset_encoding)
        -- The quickfix list creation has been removed from here
      else
        util.jump_to_location(result, offset_encoding)
      end
    end
    return handler
  end
  local signs = {
    { name = "DiagnosticSignError", text = "" },
    { name = "DiagnosticSignWarn", text = "" },
    { name = "DiagnosticSignHint", text = "" },
    { name = "DiagnosticSignInfo", text = "" },
  }

  -- for _, sign in ipairs(signs) do
  --   vim.fn.sign_define(sign.name, { texthl = sign.name, text = sign.text, numhl = "" })
  -- end

  local config = {
    -- disable virtual text
    virtual_text = true,
    -- show signs
    signs = {
      active = signs,
    },
    update_in_insert = true,
    underline = false,
    severity_sort = true,
    float = {
      focusable = false,
      style = "minimal",
      border = "rounded",
      source = "always",
      header = "",
      prefix = "",
    },
  }

  vim.diagnostic.config(config)

  --vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
  --  border = "rounded",
  --})

  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
    border = "rounded",
  })
  vim.lsp.handlers["textDocument/definition"] = goto_definition('e')
end

local function lsp_highlight_document(client)
  -- Set autocommands conditional on server_capabilities
  if false then
    -- if client.server_capabilities.documentHighlight then
    vim.api.nvim_exec(
      [[
      augroup lsp_document_highlight
        autocmd! * <buffer>
        autocmd CursorHold <buffer> lua vim.lsp.buf.document_highlight()
        autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
      augroup END
    ]],
      false
    )
  end
end

local function first_only_on_list (options)
  if options and options.items and #options.items > 0 then
    -- Just take the first item and jump to it
    local item = options.items[1]
    vim.fn.setqflist({}, ' ', {items = {item}, title = options.title})
    vim.cmd.cfirst()
    -- Immediately close the quickfix list
    vim.cmd.cclose()
  end
end

local function lsp_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  vim.keymap.set("n", "gd", function()
    vim.cmd('w')
    vim.cmd('vsplit')
    vim.lsp.buf.definition({ on_list = first_only_on_list })
  end, { buffer = bufnr, desc = "Go to definition in vsplit", noremap = true, silent = true })
  vim.keymap.set("n", "gD", function()
    vim.cmd('w')
    vim.cmd('vsplit')
    vim.lsp.buf.type_definition({ on_list = first_only_on_list })
  end, { buffer = bufnr, desc = "Go to type definition in vsplit", noremap = true, silent = true })

  vim.keymap.set("n", "gi", function()
    vim.cmd('w')
    vim.lsp.buf.definition({ on_list = first_only_on_list })
  end, { buffer = bufnr, desc = "Go to definition", noremap = true, silent = true })

  vim.keymap.set("n", "gI", function()
    vim.cmd('w')
    vim.lsp.buf.type_definition({ on_list = first_only_on_list })
  end, { buffer = bufnr, desc = "Go to type definition", noremap = true, silent = true })

  vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>K", "<cmd>lua vim.lsp.buf.hover()<CR>", opts)
  vim.keymap.set("n", "<leader>K", vim.lsp.buf.hover, { buffer = bufnr, desc = "Show hover information", noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>rn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts)
  vim.keymap.set('n', '<leader>gc', function()
    vim.lsp.buf.code_action()
  end, { buffer = bufnr, desc = "LSP Code Actions", noremap = true, silent = true })
  -- vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>gr', '<cmd>RustRunnables<CR>', opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "[d", '<cmd>lua vim.diagnostic.goto_prev({ border = "rounded" })<CR>', opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "]d", '<cmd>lua vim.diagnostic.goto_next({ border = "rounded" })<CR>', opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>q", "<cmd>lua vim.diagnostic.setloclist()<CR>", opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "<leader>f", "<cmd>lua vim.diagnostic.open_float()<CR>", opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "gi", "<cmd>lua vim.lsp.buf.definition()<CR><C-w>h:wq<CR>", opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "gn", "<cmd>lua vim.lsp.buf.definition()<CR><C-w>T", opts)
  -- vim.api.nvim_buf_set_keymap(bufnr, "n", "<C-k>", "<cmd>lua vim.lsp.buf.signature_help()<CR>", opts)
  local telescope_builtin_ok, telescope_builtin = pcall(require, "telescope.builtin")
  vim.keymap.set("n", "gr", function()
    if telescope_builtin_ok then
      telescope_builtin.lsp_references({
        include_declaration = false,
        show_line = true,
        trim_text = true
      })
    else
      vim.lsp.buf.references()
    end
  end, { buffer = bufnr, desc = "Find references (Telescope if available)", noremap = true, silent = true })
  vim.cmd [[ command! Format execute 'lua vim.lsp.buf.formatting()' ]]
end
M.on_attach = function(client, bufnr)
  --client.offset_encoding =  utf8
  -- if client.server_capabilities.documentHighlight then
  --     vim.cmd [[
  --       hi LspReferenceRead cterm=bold ctermbg=red guibg=LightYellow
  --       hi LspReferenceText cterm=bold ctermbg=red guibg=LightYellow
  --       hi LspReferenceWrite cterm=bold ctermbg=red guibg=LightYellow
  --       augroup lsp_document_highlight
  --         autocmd! * <buffer>
  --         autocmd CursorHold <buffer> lua vim.lsp.buf.document_highlight()
  --         autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
  --       augroup END
  --     ]]
  -- end
  lsp_keymaps(bufnr)
  -- lsp_highlight_document(client)
end

local status_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if not status_ok then
  return
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
M.capabilities = cmp_nvim_lsp.default_capabilities(capabilities)

return M
