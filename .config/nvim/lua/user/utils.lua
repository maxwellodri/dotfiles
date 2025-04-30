local M = {}

-- Function to get clipboard content - Wayland and X11 (xclip) specific
-- Returns a table with:
-- - content: clipboard content as string
-- - exit_code: 0 (success) or 1 (error)
-- - error_msg: error message if exit_code is 1
-- - env: "wayland", "x11", or "none"
function M.get_clipboard()
  local result = {
    content = "",
    exit_code = 1,
    error_msg = "",
    env = "none"
  }
  -- Check for Wayland or X11 environment
  local wayland_display = os.getenv("WAYLAND_DISPLAY")
  local display = os.getenv("DISPLAY")
  
  if wayland_display and wayland_display ~= "" then
    -- Wayland environment - use wl-paste
    result.env = "wayland"
    local success, output = pcall(vim.fn.system, 'wl-paste --primary')
    if success and vim.v.shell_error == 0 then
      result.content = output
      result.exit_code = 0
    else
      -- Try clipboard selection if primary fails
      success, output = pcall(vim.fn.system, 'wl-paste')
      if success and vim.v.shell_error == 0 then
        result.content = output
        result.exit_code = 0
      else
        result.error_msg = "Failed to get clipboard content using wl-paste. Is wl-clipboard installed?"
      end
    end
  elseif display and display ~= "" then
    -- X11 environment - use xclip
    result.env = "x11"
    local success, output = pcall(vim.fn.system, 'xclip -selection clipboard -o')
    if success and vim.v.shell_error == 0 then
      result.content = output
      result.exit_code = 0
    else
      result.error_msg = "Failed to get clipboard content using xclip. Is xclip installed?"
    end
  else
    result.error_msg = "Neither WAYLAND_DISPLAY nor DISPLAY environment variables are defined. This function requires a Wayland or X11 environment."
  end
  return result
end

-- Function to write content to a temporary file
-- Returns a table with:
-- - path: path to the temporary file or nil if error
-- - exit_code: 0 (success) or 1 (error)
-- - error_msg: error message if exit_code is 1
function M.write_to_temp(contents)
  local result = {
    path = nil,
    exit_code = 1,
    error_msg = ""
  }
  -- Generate temporary file path
  local temp_file = os.tmpname()
  -- Try to open file for writing
  local file = io.open(temp_file, 'w')
  if not file then
    result.error_msg = "Failed to create temporary file"
    return result
  end
  -- Write content to file
  local success, err = pcall(function()
    file:write(contents)
    file:close()
  end)
  if not success then
    result.error_msg = "Failed to write to temporary file: " .. tostring(err)
    return result
  end
  -- Return success
  result.path = temp_file
  result.exit_code = 0
  return result
end

return M
