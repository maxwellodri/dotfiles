local wezterm = require("wezterm")

local config = {}

config.front_end = "Software"
config.max_fps = 60

-- Disable multiplexer — we use tmux
config.unix_domains = {}
config.skip_close_confirmation_for_processes_named = { "*" }
config.window_close_confirmation = "NeverPrompt"

-- Font
config.font = wezterm.font("RiceManFontFamily")
config.font_size = 12

-- Colors (from alacritty config)
config.colors = {
	foreground = "#e5e5e5",
	background = "#141720",
	cursor_bg = "#cccccc",
	cursor_fg = "#141720",
	cursor_border = "#cccccc",
	ansi = {
		"#000000", -- black
		"#f80101", -- red
		"#00cd00", -- green
		"#cdcd00", -- yellow
		"#5c5cff", -- blue
		"#ff00ff", -- magenta
		"#00cdcd", -- cyan
		"#e5e5e5", -- white
	},
	brights = {
		"#7f7f7f", -- black
		"#ff0000", -- red
		"#00ff00", -- green
		"#ffff00", -- yellow
		"#5c5cff", -- blue
		"#ff00ff", -- magenta
		"#00ffff", -- cyan
		"#ffffff", -- white
	},
}

-- Cursor
config.default_cursor_style = "SteadyBlock"
config.cursor_blink_rate = 0

-- Window
config.window_padding = {
	left = 1,
	right = 1,
	top = 1,
	bottom = 1,
}

-- Scrollback
config.scrollback_lines = 10000

-- Key bindings
config.keys = {
	{
		key = "PageUp",
		mods = "SHIFT",
		action = wezterm.action.ScrollByPage(-1),
	},
	{
		key = "PageDown",
		mods = "SHIFT",
		action = wezterm.action.ScrollByPage(1),
	},
}

-- Disable tabs (we use tmux)
config.enable_tab_bar = false

-- Disable hyperlink rules (hints = [] in alacritty)
config.hyperlink_rules = {}

return config
