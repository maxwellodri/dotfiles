---@diagnostic disable-next-line: undefined-global
local mp = mp
local file_list = {}
-- Function to toggle file in list
local function toggle_file()
    local path = mp.get_property("path")
    if not path then return end
    
    local found = false
    for i, file in ipairs(file_list) do
        if file == path then
            mp.osd_message("Removed file from list: " .. path)
            table.remove(file_list, i)
            found = true
            break
        end
    end
    if not found then
        mp.osd_message("Appending file to list: " .. path)
        table.insert(file_list, path)
    end
end
-- Function to escape a string for shell
local function shell_escape(str)
    -- Escape single quotes by ending the quoted string, adding an escaped quote, then starting a new quoted string
    return "'" .. str:gsub("'", "'\\''") .. "'"
end
-- Function to print the list on exit as a single shell-escaped string
local function print_file_list()
    if #file_list == 0 then
        return
    end
    local escaped_files = {}
    for _, file in ipairs(file_list) do
        table.insert(escaped_files, shell_escape(file))
    end
    local file_string = table.concat(escaped_files, " ")
    print(file_string)
end
-- Bind ctrl-x to toggle the file
mp.add_key_binding("ctrl+x", "toggle-file", toggle_file)
-- Register shutdown hook to print the list
mp.register_event("shutdown", print_file_list)
