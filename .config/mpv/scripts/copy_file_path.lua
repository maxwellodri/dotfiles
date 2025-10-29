local mp = mp
local function copy_path_to_clipboard()
    local path = mp.get_property("path")
    if not path or path == "" then
        mp.osd_message("No file path available", 2)
        return
    end
    local safe_path = path:gsub("'", "'\\''")
    local cmd
    if os.getenv("WAYLAND_DISPLAY") then
        cmd = string.format("echo -n '%s' | wl-copy", safe_path)
    else
        cmd = string.format("echo -n '%s' | xclip -selection clipboard; echo -n '%s' | xclip -selection primary", safe_path, safe_path)
    end
    local success, _, code = os.execute(cmd)
    local success_flag
    if type(success) == "number" then
        success_flag = (success == 0)
    else
        success_flag = success
    end
    if success_flag then
        mp.osd_message("Path copied: " .. path, 1)
    else
        mp.osd_message("Failed to copy path (error " .. (code or "unknown") .. ")", 1)
    end
end
mp.add_key_binding("Ctrl+Shift+y", "copy-path", copy_path_to_clipboard)
