local notes_dir = vim.fn.expand("~/Documents/notes/")
local socket_path = "/tmp/nvim/notes" .. vim.fn.getpid() .. ".sock"
local socket_handle = nil

local function is_notes_buffer(bufnr)
  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  if bufpath == "" then return false end
  local realpath = vim.fn.resolve(vim.fn.fnamemodify(bufpath, ":p"))
  return vim.startswith(realpath, notes_dir)
end

local function count_active_sockets()
  local count = 0
  local dir_handle = vim.loop.fs_scandir("/tmp/nvim")
  if dir_handle then
    while true do
      local name = vim.loop.fs_scandir_next(dir_handle)
      if not name then break end
      if name:match("^notes.*%.sock$") then
        count = count + 1
      end
    end
  end
  return count
end

local function update_socket()
  local has_notes_buffer = false
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and is_notes_buffer(bufnr) then
      has_notes_buffer = true
      break
    end
  end
  
  local should_have_socket = has_notes_buffer
  local has_socket = socket_handle ~= nil
  
  if should_have_socket and not has_socket then
    vim.fn.mkdir("/tmp/nvim", "p")
    socket_handle = vim.fn.serverstart(socket_path)
  elseif not should_have_socket and has_socket then
    vim.fn.serverstop(socket_path)
    socket_handle = nil
    if count_active_sockets() == 0 then
      vim.loop.fs_rmdir("/tmp/nvim")
    end
  end
end

vim.api.nvim_create_autocmd({"BufEnter", "BufAdd", "BufDelete", "BufWipeout"}, {
  callback = function()
    vim.schedule(update_socket)
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if socket_handle then
      vim.fn.serverstop(socket_path)
      if count_active_sockets() == 0 then
        vim.loop.fs_rmdir("/tmp/nvim")
      end
    end
  end,
})

vim.api.nvim_create_user_command('NotesEdit', function(opts)
  vim.cmd('edit ' .. opts.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command('NotesVsplit', function(opts)
  vim.cmd('vsplit ' .. opts.args)
end, { nargs = 1 })

update_socket()
