# Wayland Migration TODO

Files needing changes before moving from X11 to Wayland. Target: avoid XWayland entirely.

## Clipboard (swap xclip → wl-copy/wl-paste)

- `.zshrc` — `vi-yank-xclip` uses `xclip -i`
- `.config/tmux/tmux.conf` — hardcoded `xclip -selection clipboard`, use `_tmux_copy` instead
- `scripts/torr` — `xclip -o` to read clipboard
- `scripts/appender` — `xclip -sel clip -o` to read clipboard
- `scripts/interactive_bookmarks.sh` — `xclip -selection clipboard`
- `scripts/wholescreensave` — `maim` + `xclip -se c`
- `scripts/colorpicker` — `xcolor` + `xclip`, use `hyprpicker + wl-copy`
- `scripts/validate_fixes.sh` — `xclip` then `xsel` fallback, add `wl-copy` as first option
- `scripts/system_diagnostics.sh` — `xclip` then `xsel` fallback, add `wl-copy` as first option
- `.config/dotfiles/dwm_faucet.sh` — `xclip -selection primary -o`, use `wl-paste -p`

## st Terminal (needs replacement)

- `scripts/get_reminders.sh` — `st -f ... -e nvim`
- `scripts/open_reminders.rem.sh` — `st -f ... -e nvim`
- `scripts/open_project.sh` — `st -d ... -e sh -c`
- `scripts/stcmd` — `st -e zsh`
- `.zshrc` — `_sterm` function uses `st -d .`
- `.config/nvim/init.vim` — `st -d` terminal opener
- `.config/faucet/faucet.yaml` — `st -e sh -c` in st_dir command
- `.pam_environment` — `TERM='st'`
- `scripts/nvim` — sets terminal title to `st` (cosmetic)

## feh Image Viewer (→ imv + swaybg)

- `scripts/as_qr` — QR code display
- `scripts/screenrecord.sh` — screenshot preview
- `scripts/background_set.sh` — wallpaper setter (`feh --bg-fill` → `swaybg`)
- `.config/mimeapps.list` — default image handler is `feh.desktop`
- `.config/faucet/faucet.yaml` — image/QR display commands

## X11-Only Configs (full replacement needed)

### Window managers / compositors

- `.config/X11/xinitrc` — X11 session startup → compositor config or `exec` in `.zprofile`
- `.config/bspwm/bspwmrc` — bspwm WM config → sway/hyprland config
- `.config/i3/config.base` — i3 base config → sway config (mostly compatible)
- `.config/i3/config.laptop` — i3 laptop config → sway config
- `.config/i3/config.thinkpad` — i3 thinkpad config → sway config
- `.config/i3/config.pc` — i3 PC config → sway config
- `.config/i3/config.chromebook` — i3 chromebook config → sway config
- `.config/sxhkd/sxhkdrc` — X11 key daemon → swhkd / xremap / compositor-native keybinds
- `.config/picom/picom.conf` — X11 compositor → Wayland compositor handles natively
- `lemonbar/bar.sh` — X11 bar → waybar / eww

### Display / session management

- `.zprofile.thinkpad` — `startx`
- `.zprofile.pc` — `startx`
- `.zprofile.hackerman` — `startx`
- `.zprofile.laptop` — `startx`, i3 workspace refs
- `.bash_profile.thinkpad` — `setxkbmap`, `startx`
- `.bash_profile.laptop` — `startx`
- `.config/sh/shrc` — aliases for `xrdb`, `sxhkd`, `bspwm`, `i3`, `picom`

### Input / hardware

- `scripts/set_kb_map` — `setxkbmap` → `xkb_options` in compositor config or `swaymsg`
- `scripts/Huion610ProTablet.sh` — `xsetwacom` → `swaymsg input` / tablet config in compositor
- `scripts/toggle_rotation.sh` — `xrandr` → `wlr-randr` or compositor-specific

### Screen capture / recording

- `scripts/screenrecord.sh` — `xrandr`, `import`, `x11grab` → `wf-recorder`, `slurp` + `grim`

### Window manipulation

- `scripts/killx` — `xdotool windowkill` → `swaymsg kill` / compositor-specific

## Shell Aliases (`.config/sh/shrc`)

- `sxhkdrc` → sxhkd key daemon
- `bspwmrc` → bspwm WM
- `xres` → xrdb/Xresources
- `i3rc` → i3 WM
- `i3tag` → i3 WM
- `i3sbar` → i3status bar
- `picomrc` → picom compositor
- `screensave` → `xclip` image extraction

## Wayland Packages Already Present

Already added alongside X11 counterparts — no removals needed for dual-support:

- `ydotool` (alongside `xdotool`)
- `wl-clipboard` (alongside `xclip`, `xsel`)
- `grim` + `slurp` (alongside `shotgun`, `hacksaw`)
- `imv` + `swaybg` (alongside `feh`)
- `dmenu-wl` (alongside `dmenu`)
- `hyprpicker` (alongside `xcolor`)
- `wf-recorder` (alongside `x11grab`)
- `wlr-randr` (alongside `xrandr`)

## Browser Window Management

- ungoogled-chromium — used by the capitalism shopping skill via Playwright MCP. Configure compositor window rules to toggle visibility of the shopping browser window (e.g. move to hidden workspace, minimize, or set opacity to 0). This lets the agent browse in the background while user intervention (CAPTCHA/login) is only needed when pinged.
