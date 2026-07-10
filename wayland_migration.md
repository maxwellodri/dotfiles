# Wayland Migration TODO

Files needing changes before moving from X11 to Wayland. Target: avoid XWayland entirely.

## Clipboard (swap xclip → wl-copy/wl-paste)

**Done** — routed callers through `scripts/clipboard`, a unified X11/Wayland
primitive (auto-detects `wl-clipboard` vs `xclip`; supports `-t/--type` and
`-p/--primary`). Migrated:

- ✅ `.zshrc` — `vi-yank-xclip` → `clipboard`
- ✅ `.config/tmux/tmux.conf` — both copy binds → `clipboard`
- ✅ `scripts/torr` — reads primary selection via `clipboard -p`
- ✅ `scripts/appender` — `clipboard`
- ✅ `scripts/validate_fixes.sh` — xclip/xsel ladder → `clipboard`
- ✅ `scripts/system_diagnostics.sh` — ladder → `clipboard < file`
- ❌ `scripts/wholescreensave` — removed; `super+shift+s` (`scripts/screenshot`, already X11/Wayland-aware) is the replacement

**Remaining** (X11-only tools, deferred):

- `scripts/interactive_bookmarks.sh` — `xclip -selection clipboard`
- `scripts/colorpicker` — `xcolor` + `xclip`, use `hyprpicker + wl-copy`
- `.config/dotfiles/dwm_faucet.sh` — `xclip -selection primary -o` (STAYS X11; dwm is an X11-only WM, no Wayland target)

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
- `.config/mimeapps.list` ✅ — default image handler is now `imv.desktop` (jpeg/png/gif/svg/webp)
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

## pi herald extension (focus detection)

- `pi/extensions/herald.ts` — `focusedWindowPid()` suppresses "agent done"
  notifications when the user is already looking at the pi instance. The X11
  path uses `xdotool getactivewindow` + `getwindowpid`. The Wayland branch is a
  **stub returning `null`**, which makes `isUserLooking()` default to "not
  looking" (notifications always fire). Implement with compositor-specific IPC,
  returning the focused top-level window's owning PID so the existing
  tmux-client ancestor check keeps working:
  - sway / wlroots — `swaymsg -t get_tree` (focused container's `pid`)
  - Hyprland — `hyprctl activewindow -j` → `.pid`
  - GNOME/mutter — `gdbus ... org.gnome.Shell`
  - KWin — `qdbus org.kde.KWin`
  - generic — `wlr-foreign-toplevel-management` (needs a helper; no simple CLI)
