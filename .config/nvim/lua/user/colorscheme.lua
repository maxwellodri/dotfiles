-- require("gruvbox").setup({
--   undercurl = true,
--   underline = true,
--   bold = false,
--   italic = false,
--   strikethrough = false,
--   invert_selection = false,
--   invert_signs = false,
--   invert_tabline = false,
--   invert_intend_guides = false,
--   inverse = true, -- invert background for search, diffs, statuslines and errors
--   contrast = "", -- can be "hard", "soft" or empty string
--   palette_overrides = {},
--   dim_inactive = false,
--   transparent_mode = false,
--   overrides = {
--     Identifier = {fg = "#ffffff"}
--   }
-- })
vim.cmd("colorscheme gruvbox")
vim.o.background = "dark" -- or "light" for light mode

-- Set 'mut' keyword to gruvbox red
-- local gruvbox_yellow = vim.api.nvim_get_hl_by_name('GruvboxYellow', 0).foreground
--vim.api.nvim_set_hl(0, '@type.qualifier.rust', {fg = gruvbox_red })

-- Grab the colors
local purple = vim.api.nvim_get_hl_by_name('GruvboxPurple', 0).foreground
local purple_bold = vim.api.nvim_get_hl_by_name('GruvboxPurpleBold', 0).foreground
local yellow = vim.api.nvim_get_hl_by_name('GruvboxYellow', 0).foreground
local red = vim.api.nvim_get_hl_by_name('GruvboxRed', 0).foreground
local blue = vim.api.nvim_get_hl_by_name('GruvboxBlue', 0).foreground
local white = vim.api.nvim_get_hl_by_name('Normal', 0).foreground
local aqua = vim.api.nvim_get_hl_by_name('GruvboxAqua', 0).foreground
local custom_purple = '#bb8ffc'
-- local custom_green = '#92ef45'
local custom_green = '#9ed841'

vim.api.nvim_set_hl(0, '@keyword.rust', {fg = red})
vim.api.nvim_set_hl(0, '@lsp.type.interface.rust', {fg = custom_purple})
vim.api.nvim_set_hl(0, '@lsp.type.selfKeyword.rust', {fg = white})
vim.api.nvim_set_hl(0, '@lsp.type.enum.rust', {fg = yellow })
vim.api.nvim_set_hl(0, '@lsp.type.struct.rust', {fg = yellow })
vim.api.nvim_set_hl(0, '@lsp.type.union.rust', {fg = red })
vim.api.nvim_set_hl(0, '@type.qualifier.rust', {fg = red })
vim.api.nvim_set_hl(0, '@lsp.type.decorator.rust', {fg = aqua })
vim.api.nvim_set_hl(0, '@lsp.type.namespace.rust', {fg = blue })
vim.api.nvim_set_hl(0, '@lsp.type.derive.rust', {fg = custom_green })

-- Set structs and enums to GruvboxYellow
vim.api.nvim_set_hl(0, '@struct.rust', {fg = yellow})
vim.api.nvim_set_hl(0, '@enum.rust', {fg = yellow})

-- vim.cmd([[colorscheme gruvbox]])
-- vim.cmd('colorscheme base16-gruvbox-dark-hard')
-- Alternatively, you can provide a table specifying your colors to the setup function.







-- vim.cmd('hi clear')
-- require('base16-colorscheme').setup({
--      base00 = '#282828', base01 = '#3c3836', base02 = '#504945', base03 = '#665c54',
--      base04 = '#bdae93', base05 = '#d5c4a1', base06 = '#ebdbb2', base07 = '#fbf1c7',
--      base08 = '#fb4934', base09 = '#fe8019', base0A = '#fabd2f', base0B = '#8ec07c',
--      base0C = '#8ec07c', base0D = '#b8bb26', base0E = '#d3869b', base0F = '#d65d0e'
-- })

-- require('base16-colorscheme').setup({
--      base00 = '#ffffff', base01 = '#3c3836', base02 = '#ffffff', base03 = '#ffffff',
--      base04 = '#ffffff', base05 = '#d5c4a1', base06 = '#ffffff', base07 = '#ffffff',
--      base08 = '#ffffff', base09 = '#fe8019', base0A = '#ffffff', base0B = '#ffffff',
--      base0C = '#ffffff', base0D = '#ffffff', base0E = '#ffffff', base0F = '#ffffff'
-- })
