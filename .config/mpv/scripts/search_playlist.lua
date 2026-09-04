-- Ctrl+Shift+s: dmenu search over the current playlist; jump to the selected entry
-- (equivalent to pressing playlist-next/prev until reaching it).
-- Escape closes dmenu (exit status 1) -> no-op.
-- Unmatched/partial input (dmenu echoes what was typed) -> no-op.

local mp = mp

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function search_and_jump()
    local playlist = mp.get_property_native("playlist")
    if not playlist or #playlist == 0 then
        mp.osd_message("Playlist is empty")
        return
    end

    -- Prefer filenames over titles; show the full path when basenames collide
    local counts = {}
    for _, entry in ipairs(playlist) do
        local base = basename(entry.filename or "")
        counts[base] = (counts[base] or 0) + 1
    end

    local index_of = {}
    local lines = {}
    for i, entry in ipairs(playlist) do
        local display = basename(entry.filename or "")
        if counts[display] > 1 then
            display = entry.filename
        end
        index_of[display] = i - 1 -- mpv playlist indices are 0-based
        lines[#lines + 1] = display
    end

    local result = mp.command_native({
        name = "subprocess",
        args = { "dmenu", "-i", "-l", "20", "-p", "Jump to" },
        stdin_data = table.concat(lines, "\n"),
        playback_only = false, -- don't pause/kill playback while dmenu is open
        capture_stdout = true,
    })
    if not result or result.status ~= 0 then
        return -- escape (status 1) or dmenu failure: no-op
    end

    local choice = result.stdout:gsub("\n+$", "")
    local index = index_of[choice]
    if not index then
        return -- partial/custom input not in the playlist: no-op
    end

    mp.commandv("playlist-play-index", index)
end

mp.add_key_binding("ctrl+shift+s", "search-playlist", search_and_jump)
