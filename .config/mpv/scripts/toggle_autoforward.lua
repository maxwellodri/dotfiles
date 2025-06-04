local autoplay_and_autoforward = true

-- Function to toggle autoplay/autoforward state
function toggle_autoplay_autoforward()
    autoplay_and_autoforward = not autoplay_and_autoforward
    
    if autoplay_and_autoforward then
        -- Enable autoplay and disable looping
        mp.set_property("loop-file", "no")
        mp.set_property("keepopen", "no")
        mp.set_property("image-display-duration", "2")
        mp.osd_message("Autoplay & Autoforward: Enabled")
        mp.msg.info("Autoplay and autoforward enabled")
    else
        -- Disable autoplay, enable looping
        mp.set_property("loop-file", "inf")
        mp.set_property("keepopen", "yes")
        mp.set_property("image-display-duration", "inf")
        mp.osd_message("Autoplay & Autoforward: Disabled (Looping)")
        mp.msg.info("Autoplay and autoforward disabled, looping enabled")
    end
end

-- Register key binding (Ctrl+a)
mp.add_key_binding("Ctrl+a", "toggle_autoplay_autoforward", toggle_autoplay_autoforward)
mp.set_property("image-display-duration", "2")
