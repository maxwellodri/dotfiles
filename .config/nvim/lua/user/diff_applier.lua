local utils = require('user.utils')
local M = {}

-- Function to apply diff from a file
-- Returns a table with:
-- - success: boolean indicating success or failure
-- - exit_code: 0 (success) or 1 (error)
-- - error_msg: error message if success is false
function M.apply_diff_from_file(file_path)
  local result = {
    success = false,
    exit_code = 1,
    error_msg = ""
  }
  -- Check if in git repository
  local success, _ = pcall(vim.fn.system, 'git rev-parse --is-inside-work-tree')
  if not success or vim.v.shell_error ~= 0 then
    result.error_msg = "Not in a git repository. This function requires a git repository."
    return result
  end
  -- Apply the diff using git apply
  local cmd = 'git apply ' .. file_path
  local cmd_success, output = pcall(vim.fn.system, cmd)
  if cmd_success and vim.v.shell_error == 0 then
    result.success = true
    result.exit_code = 0
    return result
  else
    result.error_msg = "Failed to apply diff: " .. tostring(output)
    return result
  end
end

-- Function to apply diff from clipboard
-- Combines the other utility functions
function M.clipboard_to_diff()
  -- Step 1: Get clipboard content
  local clipboard_result = utils.get_clipboard()
  if clipboard_result.exit_code ~= 0 then
    vim.notify("Clipboard error: " .. clipboard_result.error_msg, vim.log.levels.ERROR)
    return false
  end
  -- Step 2: Validate clipboard content looks like a diff
  local diff_content = clipboard_result.content
  if diff_content == '' then
    vim.notify('Clipboard is empty', vim.log.levels.ERROR)
    return false
  end
  if not string.match(diff_content, "^diff ") and
     not string.match(diff_content, "^%-%-%- ") and
     not string.match(diff_content, "^%+%+%+ ") then
    vim.notify('Clipboard content does not appear to be a valid diff', vim.log.levels.ERROR)
    return false
  end
  -- Step 3: Write diff to temporary file
  local temp_result = utils.write_to_temp(diff_content)
  if temp_result.exit_code ~= 0 then
    vim.notify("Error creating temporary file: " .. temp_result.error_msg, vim.log.levels.ERROR)
    return false
  end
  -- Step 4: Apply the diff
  local apply_result = M.apply_diff_from_file(temp_result.path)
  -- Step 5: Clean up temporary file
  os.remove(temp_result.path)
  -- Step 6: Handle result
  if apply_result.success then
    vim.notify('Successfully applied diff from clipboard (' .. clipboard_result.env .. ' environment)', vim.log.levels.INFO)
    vim.cmd('checktime') -- Refresh Neovim buffer to show changes
    return true
  else
    vim.notify('Failed to apply diff: ' .. apply_result.error_msg, vim.log.levels.ERROR)
    return false
  end
end

-- Set up a command to call the function
vim.api.nvim_create_user_command('ApplyClipboardDiff', function()
  M.clipboard_to_diff()
end, {})

-- Set up an optional keymap (modify as needed)
vim.keymap.set('n', '<leader>aD', M.clipboard_to_diff, { noremap = true, desc = 'Apply diff from clipboard' })

return M
