---@diagnostic disable-next-line: undefined-global
local mp = mp
local touch_pending = false
local timeout_id = nil

local function touch_file()
    if touch_pending then
        local path = mp.get_property("path")
        if path then
            os.execute("touch -- '" .. path:gsub("'", "'\\''") .. "'")
            mp.osd_message("File touched: " .. path)
        else
            mp.osd_message("No file to touch")
        end
        touch_pending = false
        if timeout_id then
            timeout_id:kill()
            timeout_id = nil
        end
    else
        mp.osd_message("Press Ctrl+T again to confirm touch")
        touch_pending = true
        if timeout_id then
            timeout_id:kill()
        end
        timeout_id = mp.add_timeout(5, function()
            touch_pending = false
            timeout_id = nil
        end)
    end
end

local function on_file_change(_, _)
    touch_pending = false
    if timeout_id then
        timeout_id:kill()
        timeout_id = nil
    end
end

mp.observe_property("path", "string", on_file_change)
mp.add_key_binding("ctrl+t", "confirm-touch", touch_file)
