---@diagnostic disable-next-line: undefined-global
local mp = mp

local delete_pending = false

local function confirm_delete()
    if delete_pending then
        local path = mp.get_property("path")
        if path then
            os.execute("rm -- '" .. path:gsub("'", "'\\''") .. "'")
            mp.osd_message("File deleted: " .. path)
        else
            mp.osd_message("No file to delete")
        end
        delete_pending = false
    else
        mp.osd_message("Press Ctrl+d again to confirm deletion")
        delete_pending = true
        mp.add_timeout(5, function() delete_pending = false end) -- Reset after 5 seconds
    end
end

mp.add_key_binding("ctrl+d", "confirm-delete", confirm_delete)
