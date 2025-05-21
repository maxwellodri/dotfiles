local mp = mp

local function copy_url_to_clipboard()
    local url = mp.get_property("metadata/comment")
    
    if not url or url == "" then
        mp.osd_message("No URL found in metadata", 2)
        return
    end
    
    local safe_url = url:gsub("'", "'\\''")
    
    local cmd
    if os.getenv("WAYLAND_DISPLAY") then
        cmd = string.format("echo -n '%s' | wl-copy", safe_url)
    else
        cmd = string.format("echo -n '%s' | xclip -selection clipboard", safe_url)
    end
    
    local success, exit_type, code = os.execute(cmd)
    
    local success_flag
    if type(success) == "number" then
        -- Lua 5.1 style
        success_flag = (success == 0)
    else
        -- Lua 5.2+ style
        success_flag = success
    end
    
    if success_flag then
        mp.osd_message("URL copied: " .. url, 2)
    else
        mp.osd_message("Failed to copy URL (error " .. (code or "unknown") .. ")", 2)
    end
end

mp.add_key_binding("Ctrl+y", "copy-url", copy_url_to_clipboard)
