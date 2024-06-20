local oil = require("oil")
vim.keymap.set("n", "<C-x>", "<CMD>Oil<CR>", { desc = "Open parent directory" })

local function open_file()
    local entry = oil.get_cursor_entry()
    local current_dir = oil.get_current_dir()
    local select = require('oil.actions').select.callback
    local file_path = current_dir .. entry.parsed_name

    local file_mimetype = vim.fn.system('xdg-mime query filetype "' .. file_path .. '"')
    local vimrc_mimetype = vim.fn.system('xdg-mime query filetype ~/.vimrc')
    local folder_mimetype = vim.fn.system('xdg-mime query filetype ~/')
    -- local file_application = vim.fn.system("xdg-mime query default " .. vim.fn.shellescape(file_mimetype))
    local file_application = vim.fn.system("xdg-mime query default " .. file_mimetype)
    local vim_application = vim.fn.system("xdg-mime query default " .. vimrc_mimetype)

    if file_application == vim_application or file_mimetype == folder_mimetype then
            select()
        else
            vim.fn.system(string.format("nohup xdg-open %s > /dev/null 2>&1 &", vim.fn.shellescape(file_path)))

    end
end

local function close_oil()
    oil.close()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if next(lines) == nil or (#lines == 1 and #lines[1] == 0) then
        vim.cmd('q!')
    end
end
local function query()
    local entry = oil.get_cursor_entry()
    local current_dir = oil.get_current_dir()
    local file_path = current_dir .. entry.parsed_name
    local file_mimetype = vim.fn.system('xdg-mime query filetype "' .. file_path .. '"')
    local file_application = vim.fn.system("xdg-mime query default " .. file_mimetype)
    vim.notify("mimetype: " .. file_mimetype.. "exec: ".. file_application)
end
local function open_gui_fm()
    local current_dir = oil.get_current_dir()
    vim.fn.system(string.format("nohup pcmanfm %s > /dev/null 2>&1 &", vim.fn.shellescape(current_dir)))
end
oil.setup({
    keymaps = {
        ["<CR>"] = { callback = open_file, desc = "Replacement actions.select that also used xdg-open", mode = "n" },
        ["<C-c>"] = { callback = close_oil, desc = "Replacement oil.close that also closes buffer if empter buffer", mode = "n" },
        ["<C-f>"] = { callback = query, desc = "Queries the mimetype of selected file", mode = "n" },
        ["<S-f>"] = { callback = open_gui_fm, desc = "Open current dir in gui fm (pcmanfm)", mode = "n" },
    }

})
