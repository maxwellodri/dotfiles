local M = {}

local config = {
    actions = {},
    width = 60,
    height = 10,
    border = 'rounded'
}

function M.setup(opts)
    config = vim.tbl_deep_extend('force', config, opts or {})
end

local function create_window()
    local width = config.width
    local height = config.height
    local bufnr = vim.api.nvim_create_buf(false, true)
    
    local win_opts = {
        relative = 'editor',
        width = width,
        height = height,
        row = (vim.o.lines - height) / 2,
        col = (vim.o.columns - width) / 2,
        style = 'minimal',
        border = config.border
    }
    
    local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)
    return bufnr, winnr
end

function M.show_menu()
    local visible_actions = {}
    for _, action in ipairs(config.actions) do
        if not action.visible or action.visible() then
            table.insert(visible_actions, action)
        end
    end

    if #visible_actions == 0 then
        vim.notify("No actions available", vim.log.levels.WARN)
        return
    end

    local bufnr, winnr = create_window()
    
    local lines = {}
    for i, action in ipairs(visible_actions) do
        local line = string.format("%d. %s", i, action.title)
        if action.description then
            line = line .. " - " .. action.description
        end
        table.insert(lines, line)
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    
    local opts = { silent = true, buffer = bufnr }
    
    for i = 1, #visible_actions do
        vim.keymap.set('n', tostring(i), function()
            vim.api.nvim_win_close(winnr, true)
            visible_actions[i].function()
        end, opts)
    end
    
    vim.keymap.set('n', 'q', function()
        vim.api.nvim_win_close(winnr, true)
    end, opts)
    vim.keymap.set('n', '<Esc>', function()
        vim.api.nvim_win_close(winnr, true)
    end, opts)
end

return M
