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
    { name = "DiagnosticSignError", text = "✘" },
    { name = "DiagnosticSignWarn", text = "" },
    { name = "DiagnosticSignHint", text = "⚑" },
    { name = "DiagnosticSignInfo", text = "»" },
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

local function first_only_on_list(options)
  if options and options.items and #options.items > 0 then
    local item = options.items[1]
    local uri = item.targetUri or item.uri
    local range = item.targetRange or item.range

    vim.lsp.util.jump_to_location({
      uri = uri,
      range = range
    }, 'utf-8')
  end
end

local function lsp_keymaps(bufnr)
  vim.keymap.set("n", "gd", function()
    vim.cmd('silent! w')
    vim.cmd('vsplit')
    local ok, err = pcall(vim.lsp.buf.definition, { on_list = first_only_on_list })
    if not ok then
      vim.notify("Definition failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, { buffer = bufnr, desc = "Go to definition in vsplit", noremap = true, silent = true })

  vim.keymap.set("n", "gi", function()
    vim.cmd('silent! w')
    local ok, err = pcall(vim.lsp.buf.definition, { on_list = first_only_on_list })
    if not ok then
      vim.notify("Definition failed: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, { buffer = bufnr, desc = "Go to definition", noremap = true, silent = true })
  -- vim.keymap.set("n", "gD", function()
  --   vim.cmd('w')
  --   vim.cmd('vsplit')
  --   vim.lsp.buf.type_definition({ on_list = first_only_on_list })
  -- end, { buffer = bufnr, desc = "Go to type definition in vsplit", noremap = true, silent = true })

  --vim.keymap.set("n", "gI", function()
  --  vim.cmd('w')
  --  vim.lsp.buf.type_definition({ on_list = first_only_on_list })
  --end, { buffer = bufnr, desc = "Go to type definition", noremap = true, silent = true })

  vim.keymap.set("n", "<leader>K", vim.lsp.buf.hover, { buffer = bufnr, desc = "Show hover information", noremap = true, silent = true })
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { buffer = bufnr, desc = "Rename symbol", noremap = true, silent = true })
  vim.keymap.set('n', '<leader>gc', function()
    vim.lsp.buf.code_action()
  end, { buffer = bufnr, desc = "LSP Code Actions", noremap = true, silent = true })
  vim.keymap.set('n', 'gr', function()
    vim.lsp.buf.references()
  end, { buffer = bufnr, desc = "LSP References", noremap = true, silent = true })
  vim.keymap.set('n', '<leader>rD', function()
    local d = vim.diagnostic.get(0)
    local l = {}
    for _, v in ipairs(d) do
      table.insert(l, string.format("%s:%d:%d: %s: %s",
        vim.fn.bufname(v.bufnr),
        v.lnum + 1,
        v.col + 1,
        vim.diagnostic.severity[v.severity],
        v.message))
    end
    vim.fn.setreg('+', table.concat(l, '\n'))
    print('Copied ' .. #d .. ' diagnostics')
  end)
  vim.keymap.set('n', '<leader>ge', function()
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
  end, { buffer = bufnr, desc = "Go to next issue", noremap = true, silent = true })
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
  vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
  lsp_keymaps(bufnr)
end

local status_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if not status_ok then
  return
end

local capabilities = vim.lsp.protocol.make_client_capabilities()
M.capabilities = cmp_nvim_lsp.default_capabilities(capabilities)

return M
