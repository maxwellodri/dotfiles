--bookmark light version (opt-in)
--record your playing history for each folder
--and you can choose resume to play next time
--
--OPT-IN: bookmarking is OFF by default for every folder. Press the toggle
--key (default B = shift+b) to enable it for the current folder; the choice
--is remembered. Folders you never enable (e.g. a rolling ~/Videos/youtube)
--are never tracked and never prompt to resume.
--
--Storage: all state lives in a single file under the XDG state directory
--($XDG_STATE_HOME, falling back to ~/.local/state):
--    <state-dir>/mpv/bookmark.conf
--Sectioned format:
--    [enabled]
--    /abs/path/to/folder
--    [progress]
--    /abs/path/to/folder<TAB>filename<TAB>percent
local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local M = {}

local o = {
    save_period = 30,
    toggle_key = "B"
}
options.read_options(o)

local function state_dir()
    local xdg = os.getenv("XDG_STATE_HOME")
    if xdg and #xdg > 0 then return xdg end
    return (os.getenv("HOME") or "") .. "/.local/state"
end

local state_root = state_dir() .. "/mpv"
local state_file = state_root .. "/bookmark.conf"

local state_dir_ready = false
local function ensure_state_dir()
    if state_dir_ready then return end
    os.execute("mkdir -p '" .. state_root:gsub("'", "'\\''") .. "'")
    state_dir_ready = true
end

-- in-memory mirror of the state file (loaded lazily)
local enabled = {}    -- set of opted-in folder paths
local progress = {}   -- folder -> { name = string, percent = number }
local state_loaded = false

local function sorted_keys(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

local function load_state()
    if state_loaded then return end
    state_loaded = true
    local f = io.open(state_file, "r")
    if not f then return end
    local section = nil
    for line in f:lines() do
        if line == "[enabled]" then
            section = "enabled"
        elseif line == "[progress]" then
            section = "progress"
        elseif line:sub(1, 1) == "#" or line == "" then
            -- comment / blank
        elseif section == "enabled" then
            enabled[line] = true
        elseif section == "progress" then
            local folder, name, percent = line:match("^(.-)\t(.-)\t([0-9.]+)$")
            if folder then
                progress[folder] = { name = name, percent = tonumber(percent) }
            end
        end
    end
    f:close()
end

local function write_state()
    ensure_state_dir()
    local out = io.open(state_file, "w")
    if not out then return end
    out:write("# mpv bookmark.lua state (auto-generated)\n")
    out:write("[enabled]\n")
    for _, folder in ipairs(sorted_keys(enabled)) do
        out:write(folder, "\n")
    end
    out:write("[progress]\n")
    for _, folder in ipairs(sorted_keys(progress)) do
        local p = progress[folder]
        if p.name and p.percent then
            out:write(folder, "\t", p.name, "\t", tostring(p.percent), "\n")
        end
    end
    out:close()
end

local cwd_root = utils.getcwd()

local pl_root
local pl_name
local pl_path
local pl_percent
local pl_list = {}

local pl_idx = 1
local c_idx = 1

local wait_msg

local tracking = false   -- is the periodic save timer currently running?

local function start_tracking()
    if tracking then return end
    tracking = true
    M.save_period_timer = mp.add_periodic_timer(o.save_period, M.save_mark)
end

local function stop_tracking()
    tracking = false
    if M.save_period_timer then
        M.save_period_timer:kill()
        M.save_period_timer = nil
    end
end

function M.show(msg, mllion)
    mp.commandv("show-text", msg, mllion)
end

function M.compare(s1, s2)
    local l1 = #s1
    local l2 = #s2
    local len = l2
    if l1 < l2 then
        local len = l1
    end
    for i = 1, len do
        if s1:sub(i,i) < s2:sub(i,i) then
            return -1, i-1
        elseif s1:sub(i,i) > s2:sub(i,i) then
            return 1, i-1
        end
    end
    return 0, len
end

function M.get_file_num(idx)
    if idx > #pl_list then
        return ""
    end
    local onm = pl_list[idx]:match("/([^/]+)$")
    local k = 1
    if(idx > 1) then
        local name = pl_list[idx-1]:match("/([^/]+)$")
        local _, tk = M.compare(onm, name)
        if k < tk then
            k = tk
        end
    end
    if(idx < #pl_list) then
        local name = pl_list[idx+1]:match("/([^/]+)$")
        local _, tk = M.compare(onm, name)
        if k < tk then
            k = tk
        end
    end
    while k > 1 do
        if onm:match("^[0-9]+", k-1) == nil then
            break
        end
        k = k - 1
    end
    return  onm:match("[0-9]+", k) or ""
end

function M.ld_mark()
    local p = progress[pl_root]
    if not p or not p.name or not p.percent then
        return false
    end
    pl_name = p.name
    pl_percent = p.percent
    pl_path = pl_root .. "/" .. pl_name
    if pl_percent >= 100 then
        pl_percent = 99
    end
    return true
end

function M.save_mark()
    local name = mp.get_property("filename")
    local percent = mp.get_property("percent-pos", 0)
    if name == nil or percent == 0 or pl_root == nil then return end
    if not enabled[pl_root] then return end   -- not opted in: never persist
    progress[pl_root] = { name = name, percent = percent }
    write_state()
end

function M.pause(name, paused)
    if paused then
        if M.save_period_timer then M.save_period_timer:stop() end
        M.save_mark()
    else
        if M.save_period_timer then M.save_period_timer:resume() end
    end
end

local timeout = 15 
function M.wait_jump()
    timeout = timeout - 1
    if(timeout < 1) then
        M.wait_jump_timer:kill()
        M.unbind_key()
    end
    local msg = ""
    if timeout < 10 then
        msg = "0"
    end
    msg = wait_msg.."--"..(math.modf(pl_percent*10)/10).."%--continue?"..msg..timeout.."[y/N]"
    M.show(msg, 1000)
end

function M.bind_key()
    mp.add_key_binding('y', 'resume_yes', M.key_jump)
    mp.add_key_binding('n', 'resume_not', function()
        M.unbind_key()
        M.wait_jump_timer:kill()
    end)
end

function M.unbind_key()
    mp.remove_key_binding('y')
    mp.remove_key_binding('n')
end

function M.key_jump()
    M.unbind_key()
    M.wait_jump_timer:kill()
    c_idx = pl_idx
    mp.register_event("file-loaded", M.jump_resume)
    mp.commandv("loadfile", pl_path)
end

function M.jump_resume()
    mp.unregister_event(M.jump_resume)
    mp.set_property("percent-pos", pl_percent)
    M.show("resume ok", 1500)
end

function M.toggle()
    if pl_root == nil then
        M.show("no folder to bookmark", 1500)
        return
    end
    load_state()
    if enabled[pl_root] then
        enabled[pl_root] = nil
        progress[pl_root] = nil
        stop_tracking()
        write_state()
        M.show("bookmarks: OFF for " .. pl_root, 2500)
    else
        enabled[pl_root] = true
        write_state()
        M.show("bookmarks: ON for " .. pl_root, 2500)
        start_tracking()
        M.save_mark()  -- record current position immediately
    end
end

function M.exe()
    mp.unregister_event(M.exe)
    local c_file = mp.get_property("filename")
    local c_path = mp.get_property("path")
    if(c_file == nil) then
        M.show('no file is playing', 1500)
        return
    end
    pl_root = c_path:match("(.+)/")
    load_state()

    -- Opt-in gate: do nothing (no resume, no saving) unless this folder has
    -- been enabled. Press the toggle key (default B) to enable it.
    if not enabled[pl_root] then
        return
    end

    if(not M.ld_mark()) then
        pl_name = ""
        pl_path = ""
        pl_percent = 0
    end
    local c_type = c_file:match("%.([^.]+)$")
    print("palying type:", c_type)
    local pl_exist = false
    if c_type ~= nil then
        local temp_list = utils.readdir(pl_root.."/", "files")
        table.sort(temp_list)
        for i = 1, #temp_list do
            local name = temp_list[i]
            if name:match("%."..c_type.."$") ~= nil then
                local path = pl_root.."/"..name
                table.insert(pl_list, path)
                if(pl_name == name) then
                    pl_exist = true
                    pl_idx = #pl_list
                end
                if(c_file == name) then
                    c_idx = #pl_list
                end
            end
        end
    end
    if(not pl_exist) then
        pl_path = c_path
        pl_name = c_file
        pl_idx = c_idx
    end
    if(c_idx == pl_idx) then
        mp.set_property("percent-pos", pl_percent)
        M.show("resume ok", 1500)
    else
        wait_msg = M.get_file_num(pl_idx)
        M.wait_jump_timer = mp.add_periodic_timer(1, M.wait_jump)
        M.bind_key()
    end
    start_tracking()
end

mp.add_key_binding(o.toggle_key, 'bookmark_toggle', M.toggle)
mp.add_hook("on_unload", 50, M.save_mark)
mp.observe_property("pause", "bool", M.pause)
mp.register_event("file-loaded", M.exe)
