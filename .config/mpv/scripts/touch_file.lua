---@diagnostic disable-next-line: undefined-global
local mp = mp
local touch_pending = false

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
    else
        mp.osd_message("Press Ctrl+T again to confirm touch")
        touch_pending = true
        mp.add_timeout(5, function() touch_pending = false end) -- Reset after 5 seconds
    end
end

mp.add_key_binding("ctrl+t", "confirm-touch", touch_file)
