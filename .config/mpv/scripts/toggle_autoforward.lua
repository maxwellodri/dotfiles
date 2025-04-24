local autoplay_enabled = true

-- Function to toggle autoplay state
function toggle_autoplay()
    autoplay_enabled = not autoplay_enabled
    
    if autoplay_enabled then
        mp.set_property("keepopen", "no")
        mp.set_property("image-display-duration", "5")
        mp.osd_message("Autoplay: Enabled")
        mp.msg.info("Autoplay enabled")
    else
        mp.set_property("keepopen", "yes")
        mp.set_property("image-display-duration", "inf")
        mp.osd_message("Autoplay: Disabled")
        mp.msg.info("Autoplay disabled")
    end
end

-- Register key binding (Ctrl+a)
mp.add_key_binding("Ctrl+a", "toggle_autoplay", toggle_autoplay)
