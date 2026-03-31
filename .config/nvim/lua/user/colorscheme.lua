-- Terminal true color support configuration
-- Simplified for modern terminals and tmux v3+
local function set_terminal_colors()
  -- Skip Apple Terminal as it doesn't support true colors
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then
    return
  end

  -- Enable true colors for Neovim
  if vim.fn.has('nvim') == 1 then
    vim.env.NVIM_TUI_ENABLE_TRUE_COLOR = 1
  end

  -- Enable termguicolors if supported
  if vim.fn.has('termguicolors') == 1 then
    vim.opt.termguicolors = true
  end
end

set_terminal_colors()

require("gruvbox").setup({
  terminal_colors = true, -- add neovim terminal colors
  undercurl = true,
  underline = true,
  bold = true,
  italic = {
    strings = true,
    emphasis = true,
    comments = true,
    operators = false,
    folds = true,
  },
  strikethrough = true,
  invert_selection = false,
  invert_signs = false,
  invert_tabline = false,
  invert_intend_guides = false,
  inverse = true, -- invert background for search, diffs, statuslines and errors
  contrast = "", -- can be "hard", "soft" or empty string
  palette_overrides = {},
  overrides = {},
  dim_inactive = false,
  transparent_mode = false,
})
vim.cmd("colorscheme gruvbox")

-- Set 'mut' keyword to gruvbox red
-- local gruvbox_yellow = vim.api.nvim_get_hl_by_name('GruvboxYellow', 0).foreground
--vim.api.nvim_set_hl(0, '@type.qualifier.rust', {fg = gruvbox_red })

-- -- Grab the colors
vim.api.nvim_set_hl(0, 'DesaturatedOrange', { fg = "#994d0f" })
vim.api.nvim_set_hl(0, 'DullGreen', { fg = "#a0c050" })
vim.api.nvim_set_hl(0, 'BurntYellow', { fg = "#917d0e" })
vim.api.nvim_set_hl(0, 'DullGrey', { fg = "#8d9183" })

local function to_hex(color)
  if type(color) == "string" then return color end
  if type(color) ~= "number" then return nil end
  return string.format("#%06x", color)
end

local dull_grey = to_hex(vim.api.nvim_get_hl_by_name('DullGrey', 0).foreground)
local burnt_yellow = to_hex(vim.api.nvim_get_hl_by_name('BurntYellow', 0).foreground)
local dull_green = to_hex(vim.api.nvim_get_hl_by_name('DullGreen', 0).foreground)
local desaturated_orange = to_hex(vim.api.nvim_get_hl_by_name('DesaturatedOrange', 0).foreground)
local purple = to_hex(vim.api.nvim_get_hl_by_name('GruvboxPurple', 0).foreground)
local purple_bold = to_hex(vim.api.nvim_get_hl_by_name('GruvboxPurpleBold', 0).foreground)
local yellow = to_hex(vim.api.nvim_get_hl_by_name('GruvboxYellow', 0).foreground)
local red = to_hex(vim.api.nvim_get_hl_by_name('GruvboxRed', 0).foreground)
local blue = to_hex(vim.api.nvim_get_hl_by_name('GruvboxBlue', 0).foreground)
local white = to_hex(vim.api.nvim_get_hl_by_name('Normal', 0).foreground)
local aqua = to_hex(vim.api.nvim_get_hl_by_name('GruvboxAqua', 0).foreground)
local orange = to_hex(vim.api.nvim_get_hl_by_name('GruvboxOrange', 0).foreground)
local lavender = '#bb8ffc'
local black = '#000000'
-- local lime_green = '#92ef45'
--b9bfac
local lime_green = '#9ed841'
local background = to_hex(vim.api.nvim_get_hl_by_name('GruvboxBg2', 0).foreground)
local hot_pink = '#f7029d'
local faded_red = require("gruvbox").palette.faded_red
local bright_green = '#00FF00'
local dark_navy = '#223355'
local muted_green = '#9ab84e'

vim.api.nvim_set_hl(0, 'LspInlayHint', { fg = dull_grey })
--vim.api.nvim_set_hl(0, 'LspInlayHint', { fg = desaturated_orange })

vim.api.nvim_set_hl(0, '@keyword.rust', {fg = red})
vim.api.nvim_set_hl(0, '@keyword.type.rust', { fg = red })
vim.api.nvim_set_hl(0, '@keyword.modifier.rust', { fg = red })
vim.api.nvim_set_hl(0, '@keyword.function.rust', { fg = lavender })
vim.api.nvim_set_hl(0, '@module.rust', { fg = white })
vim.api.nvim_set_hl(0, '@variable.rust', { fg = white })
vim.api.nvim_set_hl(0, '@type.rust', { fg = yellow })
vim.api.nvim_set_hl(0, '@operator.rust', { fg = white })
vim.api.nvim_set_hl(0, '@type.builtin.rust', { fg = orange })
vim.api.nvim_set_hl(0, '@variable.parameter', { fg = white })
vim.api.nvim_set_hl(0, '@function.macro.rust', { fg = muted_green })
vim.api.nvim_set_hl(0, '@punctuation.bracket.rust', {})
vim.api.nvim_set_hl(0, '@punctuation.delimiter.rust', { fg = white })

-- These only work with LSP semantic Highlighting
vim.api.nvim_set_hl(0, '@lsp.type.interface.rust', {fg = lavender})
vim.api.nvim_set_hl(0, '@lsp.type.macro.rust', { fg = dull_green })
vim.api.nvim_set_hl(0, '@lsp.type.typeAlias.rust', { fg = hot_pink })
vim.api.nvim_set_hl(0, '@lsp.type.enum.rust', { fg = lime_green })
vim.api.nvim_set_hl(0, '@lsp.type.decorator.rust', { fg = purple })
vim.api.nvim_set_hl(0, '@lsp.type.parameter.rust', { fg = white })
--vim.api.nvim_set_hl(0, '@lsp.mod.defaultLibrary.rust', { fg = lavender })
-- -- vim.api.nvim_set_hl(0, '@lsp.type.selfKeyword.rust', {fg = black})
-- vim.api.nvim_set_hl(0, '@lsp.type.enum.rust', {fg = yellow })
-- vim.api.nvim_set_hl(0, '@lsp.type.struct.rust', {fg = yellow })
-- vim.api.nvim_set_hl(0, '@lsp.type.union.rust', {fg = red })
-- vim.api.nvim_set_hl(0, '@type.qualifier.rust', {fg = red })
-- vim.api.nvim_set_hl(0, '@lsp.type.decorator.rust', {fg = aqua })
-- vim.api.nvim_set_hl(0, '@lsp.type.namespace.rust', {fg = blue })
-- vim.api.nvim_set_hl(0, '@lsp.type.derive.rust', {fg = lime_green })
-- --
-- -- Set structs and enums to GruvboxYellow
-- vim.api.nvim_set_hl(0, '@struct.rust', {fg = yellow})
-- vim.api.nvim_set_hl(0, '@enum.rust', {fg = yellow})
--
-- vim.api.nvim_set_hl(0, '@variable', {fg = white})
-- vim.api.nvim_set_hl(0, '@delimter', {fg = blue})
-- vim.api.nvim_set_hl(0, '@delimter', {fg = blue})
-- vim.api.nvim_set_hl(0, 'WinSeparator', {fg = background})


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

local M = {}
M.colors = {
  dull_grey = dull_grey,
  burnt_yellow = burnt_yellow,
  dull_green = dull_green,
  desaturated_orange = desaturated_orange,
  purple = purple,
  purple_bold = purple_bold,
  yellow = yellow,
  red = red,
  blue = blue,
  white = white,
  aqua = aqua,
  orange = orange,
  lavender = lavender,
  black = black,
  lime_green = lime_green,
  background = background,
  hot_pink = hot_pink,
  faded_red = faded_red,
  bright_green = bright_green,
  dark_navy = dark_navy,
  muted_green = muted_green,
}
return M
