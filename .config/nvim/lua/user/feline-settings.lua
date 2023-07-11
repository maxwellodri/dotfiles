local components_bottom = {
    active = {},
    inactive = {}
}
-- Insert three sections (left, mid and right) for the active statusline
table.insert(components_bottom.active, {})
table.insert(components_bottom.active, {})
table.insert(components_bottom.active, {})

-- Insert two sections (left and right) for the inactive statusline
table.insert(components_bottom.inactive, {})
table.insert(components_bottom.inactive, {})

local components_top = {
    active = {},
    inactive = {}
}
-- Insert three sections (left, mid and right) for the active statusline
table.insert(components_top.active, {})
table.insert(components_top.active, {})
table.insert(components_top.active, {})

-- Insert two sections (left and right) for the inactive statusline
table.insert(components_top.inactive, {})
table.insert(components_top.inactive, {})

components_bottom.active[1][1] = {
    provider = 'vi_mode',
    hl = function()
        return {
            name = require('feline.providers.vi_mode').get_mode_highlight_name(),
            fg = require('feline.providers.vi_mode').get_mode_color(),
            style = 'bold'
        }
    end,
    right_sep = ' '
}

-- Component that shows file info
components_bottom.active[1][3] = {
    provider = 'file_info',
    hl = {
        fg = 'white',
        bg = 'oceanblue',
        style = 'bold'
    },
    left_sep = {' ', 'slant_left_2'},
    right_sep = {'slant_right_2', ' '},
    -- Uncomment the next line to disable file icons
    -- icon = ''
}

require('feline').winbar.setup(components_top)
require('feline').setup(components_bottom)
