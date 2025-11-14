local function get_file_path()
  local filepath = vim.fn.expand('%:p')
  -- Try to get git root
  local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(vim.fn.expand('%:p:h')) .. ' rev-parse --show-toplevel')[1]
  if vim.v.shell_error == 0 and git_root then
    -- Make path relative to git root
    filepath = vim.fn.fnamemodify(filepath, ':~:.')
    local root_relative = vim.fn.substitute(filepath, '^' .. vim.fn.escape(git_root, '/') .. '/', '', '')
    if root_relative ~= filepath then
      filepath = root_relative
    else
      -- Fallback: use relative path from git root
      filepath = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':~:.')
    end
  end
  return filepath
end

local function copy_with_location()
  local mode = vim.fn.mode()
  local filepath = get_file_path()
  local line_num = vim.fn.line('.')
  local result = filepath .. ':' .. line_num
  -- Check if in visual mode
  if mode:match('[vV\22]') then -- v, V, or Ctrl-V
    -- Get selected text
    vim.cmd('normal! "xy')
    local selected = vim.fn.getreg('x')
    if selected and selected ~= '' then
      result = result .. '\n' .. selected
    end
  end
  vim.fn.setreg('+', result)
  vim.fn.setreg('"', result)
end

vim.keymap.set('n', '<leader>y', copy_with_location, { noremap = true, silent = true })
vim.keymap.set('v', '<leader>y', copy_with_location, { noremap = true, silent = true })
