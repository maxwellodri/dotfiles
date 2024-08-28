-- local options = require 'mp.options'
-- local utils = require 'mp.utils'
-- local volume_file = utils.join_path(os.getenv("HOME") .. "/.config/mpv", "volume.conf")
-- local mpv_config_file = utils.join_path(os.getenv("HOME") .. "/.config/mpv", "mpv.conf")
-- 
-- local o = {
--     volume = 100
-- }
-- 
-- options.read_options(o, "remember_volume")
-- 
-- function save_volume()
--     local volume = mp.get_property("volume")
--     mp.msg.info("Saving volume: " .. volume)
--     local file = io.open(volume_file, "w")
--     if file then
--         file:write(string.format("volume=%d\n", volume))
--         file:close()
--         mp.msg.info("Volume saved to " .. volume_file)
--     else
--         mp.msg.error("Could not open volume file for writing")
--     end
-- end
-- 
-- function load_volume()
--     local volume = nil
--     mp.msg.info("Trying to load volume from " .. volume_file)
--     local file = io.open(volume_file, "r")
--     if file then
--         volume = tonumber(file:read("*all"):match("volume=(%d+)"))
--         file:close()
--         mp.msg.info("Loaded volume from " .. volume_file .. ": " .. tostring(volume))
--     else
--         mp.msg.warn("Volume file not found")
--     end
-- 
--     if not volume then
--         mp.msg.info("Trying to load volume from " .. mpv_config_file)
--         file = io.open(mpv_config_file, "r")
--         if file then
--             for line in file:lines() do
--                 volume = tonumber(line:match("volume=(%d+)"))
--                 if volume then
--                     mp.msg.info("Loaded volume from " .. mpv_config_file .. ": " .. tostring(volume))
--                     break
--                 end
--             end
--             file:close()
--         else
--             mp.msg.warn("mpv.conf file not found")
--         end
--     end
-- 
--     if volume then
--         mp.set_property("volume", volume)
--         mp.msg.info("Volume set to " .. tostring(volume))
--     else
--         mp.msg.warn("No volume setting found, using default volume")
--     end
-- end
-- 
-- mp.register_event("shutdown", save_volume)
-- mp.register_event("file-loaded", load_volume)