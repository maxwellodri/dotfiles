local mp = mp

local function get_clipboard_content()
    local cmd
    if os.getenv("WAYLAND_DISPLAY") then
        cmd = "wl-paste"
    else
        cmd = "xclip -selection clipboard -o"
    end
    
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local content = handle:read("*a")
    handle:close()
    
    return content and content:gsub("%s+$", "") or nil
end

local function copy_url_to_clipboard()
    local url = mp.get_property("metadata/comment")
    
    if not url or url == "" then
        mp.osd_message("No URL found in metadata", 2)
        return
    end
    
    local old_clipboard = get_clipboard_content()
    
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
        success_flag = (success == 0)
    else
        success_flag = success
    end
    
    if success_flag then
        if old_clipboard == url then
            local firefox_cmd = string.format("firefox --new-tab '%s'", safe_url)
            mp.osd_message("URL opened in browser", 2)
            os.execute(firefox_cmd)
        else
            mp.osd_message("URL copied: " .. url, 0.3)
        end
    else
        mp.osd_message("Failed to copy URL (error " .. (code or "unknown") .. ")", 2)
    end
end

mp.add_key_binding("Ctrl+y", "copy-url", copy_url_to_clipboard)
