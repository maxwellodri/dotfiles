vim.lsp.set_log_level("ERROR")
require("user.lsp.handlers").setup()
Opts = {
  on_attach = require("user.lsp.handlers").on_attach,
  capabilities = require("user.lsp.handlers").capabilities,
  config = require("user.lsp.handlers").config,
}
vim.api.nvim_create_user_command('LspLog', function()
  vim.cmd('tabnew ' .. vim.lsp.get_log_path())
end, {})

vim.api.nvim_create_user_command('LspRestart', function()
  vim.lsp.stop_client(vim.lsp.get_clients())
  vim.defer_fn(function()
    vim.cmd('edit')
  end, 500)
end, {})

vim.api.nvim_create_user_command('LspInfo', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  
  local info = {}
  for _, client in ipairs(clients) do
    table.insert(info, {
      name = client.name,
      id = client.id,
      server_capabilities = client.server_capabilities,
      config = client.config,
      workspace_folders = client.workspace_folders,
      attached_buffers = vim.tbl_keys(client.attached_buffers or {}),
    })
  end
  
  local output = vim.inspect(info)
  vim.fn.setreg('+', output)
  
  vim.cmd('tabnew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, '\n'))
  vim.bo.filetype = 'lua'
  vim.bo.buftype = 'nofile'
  vim.bo.bufhidden = 'wipe'
end, {})


return Opts

-- local godot_cmd = vim.lsp.rpc.connect('127.0.0.1', 6014)
-- require('lspconfig').gdscript.setup{ cmd = godot_cmd, on_attach = Opts.on_attach, flags = { debounce_text_changes = 150, } }
