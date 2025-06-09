-- rename_file.lua
-- This script binds Ctrl+r to rename the current file using mpv's built-in input

local utils = require 'mp.utils'

-- Global variable to store current file info during rename process
local current_file_info = nil

function rename_current_file()
    -- Get the current file path
    local file_path = mp.get_property("path")
    if not file_path then
        mp.osd_message("No file currently loaded", 3)
        return
    end
    
    -- Extract directory and filename
    local dir = utils.split_path(file_path)
    local filename = mp.get_property("filename")
    
    if not filename then
        mp.osd_message("Could not get filename", 3)
        return
    end
    
    -- Store current info for the callback
    current_file_info = {
        path = file_path,
        dir = dir,
        filename = filename
    }
    
    -- Show instruction and open console with pre-filled command
    mp.osd_message("Type: script-message rename-to NEW_FILENAME", 5)
    mp.commandv("script-message-to", "console", "type", 
        string.format("script-message rename-to %s", filename))
end

function handle_rename_to(new_filename)
    if not current_file_info then
        mp.osd_message("No file info available", 3)
        return
    end
    
    if not new_filename or new_filename == "" then
        mp.osd_message("New filename is empty", 3)
        return
    end
    
    -- Remove any trailing whitespace
    new_filename = new_filename:gsub("%s+$", "")
    
    -- Check if filename actually changed
    if new_filename == current_file_info.filename then
        mp.osd_message("Filename unchanged", 2)
        return
    end
    
    -- Construct new file path
    local new_file_path = utils.join_path(current_file_info.dir, new_filename)
    
    -- Check if target file already exists
    local target_file = io.open(new_file_path, "r")
    if target_file then
        target_file:close()
        mp.osd_message("Error: File '" .. new_filename .. "' already exists", 4)
        return
    end
    
    -- Attempt to rename the file
    local success, error_msg = os.rename(current_file_info.path, new_file_path)
    
    if success then
        mp.osd_message("File renamed to: " .. new_filename, 3)
        
        -- Get current playback state to restore
        local playlist_pos = mp.get_property_number("playlist-pos")
        local time_pos = mp.get_property_number("time-pos") or 0
        local pause_state = mp.get_property_bool("pause")
        
        if playlist_pos then
            -- Remove the old entry and insert the new one at the same position
            mp.commandv("playlist-remove", playlist_pos)
            mp.commandv("loadfile", new_file_path, "insert-at", playlist_pos)
            
            -- Restore playback position and state
            mp.set_property_number("playlist-pos", playlist_pos)
            mp.commandv("seek", time_pos, "absolute")
            if pause_state then
                mp.set_property("pause", true)
            end
        else
            -- Fallback: simple reload
            mp.commandv("loadfile", new_file_path, "replace")
            mp.commandv("seek", time_pos, "absolute")
            if pause_state then
                mp.set_property("pause", true)
            end
        end
        
        -- Clear the stored info
        current_file_info = nil
    else
        mp.osd_message("Error renaming file: " .. (error_msg or "unknown error"), 4)
    end
end

mp.register_script_message("rename-to", handle_rename_to)
mp.add_key_binding("Ctrl+r", "rename_file", rename_current_file)

