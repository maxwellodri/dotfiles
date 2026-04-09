# Wayland Migration Audit

Files needing changes before moving from X11 to Wayland. Target: avoid XWayland entirely.

## Already Wayland-Aware (No Changes)

| File | Notes |
|---|---|
| `scripts/passmenu` | Checks `$WAYLAND_DISPLAY`, branches for ydotool/wl-copy vs xdotool/xclip |
| `scripts/clipboard` | Full Wayland/X11 clipboard support |
| `scripts/screenshot` | grim/slurp on Wayland, shotgun/hacksaw on X11 |
| `scripts/screendump` | Full Wayland/X11 support |
| `scripts/_pass_clear_clip` | Full Wayland/X11 support |
| `scripts/_tmux_copy` | Full Wayland/X11 support |
| `scripts/mvx` | Full Wayland/X11 clipboard support |
| `scripts/extract_rss` | Full Wayland/X11 clipboard support |
| `scripts/games` | Wayland-aware dmenu selection |
| `scripts/ffs` | Wayland-aware dmenu selection |
| `scripts/transcriptor` | Checks `wl-copy` first, falls back to `xclip` |
| `scripts/wg_switcher.sh` | Checks both `$DISPLAY` and `$WAYLAND_DISPLAY` |
| `.config/mpv/scripts/copy_file_path.lua` | Checks `$WAYLAND_DISPLAY` |
| `.config/mpv/scripts/copy-url.lua` | Checks `$WAYLAND_DISPLAY` |
| `.config/nvim/lua/user/utils.lua` | Checks `$WAYLAND_DISPLAY` |
| `.config/dotfiles/handlers/magnet_link_handler.sh` | dmenu is Wayland-aware (but `st` is not — see below) |
| `.config/dunst/dunstrc` | Has `force_xwayland = false` |

---

## Straightforward Fixes (swap xclip → wl-copy/wl-paste)

### Clipboard reads/writes without Wayland fallback

| File | Line(s) | X11-ism | Fix |
|---|---|---|---|
| `.zshrc` | 112–117 | `xclip -i` in `vi-yank-xclip` function | Add `$WAYLAND_DISPLAY` check, use `wl-copy` |
| `.config/tmux/tmux.conf` | 5 | Hardcoded `xclip -selection clipboard` | Use `_tmux_copy` script (already Wayland-aware) |
| `scripts/torr` | 3 | `xclip -o` to read clipboard | Add Wayland branch with `wl-paste` |
| `scripts/appender` | 4 | `xclip -sel clip -o` to read clipboard | Add Wayland branch with `wl-paste` |
| `scripts/interactive_bookmarks.sh` | 3 | `xclip -selection clipboard` | Add Wayland branch with `wl-copy` |
| `scripts/wholescreensave` | 6 | `maim` + `xclip -se c` | Add Wayland branch (grim + wl-copy) |
| `scripts/colorpicker` | 2 | `xcolor` + `xclip` | Add Wayland branch (hyprpicker + wl-copy) |
| `scripts/validate_fixes.sh` | 161–165 | `xclip` then `xsel` fallback | Add `wl-copy` as first option |
| `scripts/system_diagnostics.sh` | 303–310 | `xclip` then `xsel` fallback | Add `wl-copy` as first option |
| `.config/dotfiles/dwm_faucet.sh` | 8 | `xclip -selection primary -o` | Add Wayland branch with `wl-paste -p` |

### dmenu without Wayland fallback

| File | Line(s) | Fix |
|---|---|---|
| `scripts/handler` | 2 | Add Wayland check, use `dmenu-wl` |
| `scripts/text_handler.sh` | 21, 69, 85 | Add Wayland check, use `dmenu-wl` |
| `scripts/qrpass` | 22 | Add Wayland check, use `dmenu-wl` |
| `scripts/emojis` | 10, 12 | Add Wayland check, use `dmenu-wl` |

---

## Needs Rethinking (terminal, image viewer, etc.)

### `st` terminal — pick a Wayland-native replacement first

All of these hardcode `st` and need updating once a replacement is chosen (e.g. foot, alacritty, wezterm, kitty):

| File | Line(s) | Context |
|---|---|---|
| `scripts/get_reminders.sh` | 38 | `st -f ... -e nvim` |
| `scripts/open_reminders.rem.sh` | 3 | `st -f ... -e nvim` |
| `scripts/open_project.sh` | 11, 13 | `st -d ... -e sh -c` |
| `scripts/stcmd` | 26 | `st -e zsh` |
| `scripts/mp_queue_song` | 7 | `st -g ... -e sh -c` |
| `scripts/_tsp_ytdlp_with_dir` | 25 | `st -g ... -e sh -c` |
| `.zshrc` | 158 | `_sterm` function uses `st -d .` |
| `.config/nvim/init.vim` | 323 | `st -d` terminal opener |
| `.config/faucet/faucet.yaml` | 23, 41 | `st` in faucet commands |
| `.config/dotfiles/handlers/magnet_link_handler.sh` | 20 | `st -g ... -e sh -c` |
| `.pam_environment` | 1 | `TERM='st'` |
| `scripts/nvim` | 2 | Sets terminal title to `st` (cosmetic) |

### `feh` — pick a Wayland-native image viewer first

(e.g. imv, swaybg for wallpapers, loupe)

| File | Line(s) | Context |
|---|---|---|
| `scripts/handler` | 9 | Image display |
| `scripts/qrpass` | 36 | QR code display |
| `scripts/as_qr` | 25 | QR code display |
| `scripts/screenrecord.sh` | 24 | Screenshot preview |
| `scripts/background_set.sh` | 4 | Wallpaper setter (`feh --bg-fill`) |
| `.config/mimeapps.list` | 24–29 | Default image handler is `feh.desktop` |
| `.config/faucet/faucet.yaml` | 56, 67 | Image/QR display commands |

---

## Partially Wayland-Aware (needs completing)

| File | Status | What's missing |
|---|---|---|
| `scripts/emojis` | Clipboard clear (lines 3–7) is Wayland-aware | Clipboard set on line 15 uses `xclip` unconditionally |
| `scripts/_tsp_ytdlp_with_dir` | dmenu is Wayland-aware | `st` terminal for manual dir selection is not |
| `.config/dotfiles/handlers/magnet_link_handler.sh` | dmenu is Wayland-aware | `st` terminal is not |

---

## Entirely X11-Only (full replacement needed)

These configs are fundamentally X11 constructs — they need Wayland equivalents, not patches.

### Window managers / compositors

| Path | What it is | Wayland equivalent |
|---|---|---|
| `.config/X11/xinitrc` | X11 session startup | Sway/Hyprland config or `exec` in `.zprofile` |
| `.config/bspwm/bspwmrc` | bspwm WM config | sway/hyprland config |
| `.config/i3/config.base` | i3 base config | sway config (mostly compatible) |
| `.config/i3/config.laptop` | i3 laptop config | sway config |
| `.config/i3/config.thinkpad` | i3 thinkpad config | sway config |
| `.config/i3/config.pc` | i3 PC config | sway config |
| `.config/i3/config.chromebook` | i3 chromebook config | sway config |
| `.config/sxhkd/sxhkdrc` | X11 key daemon | WM-native keybinds |
| `.config/picom/picom.conf` | X11 compositor | Wayland compositor handles this natively |
| `dwm/` (entire dir) | dwm WM + statusbar scripts | sway/hyprland + waybar |
| `penrose/startup.sh` | penrose WM startup | N/A |
| `lemonbar/bar.sh` | X11 bar | waybar / eww |

### Display/session management

| Path | X11-ism |
|---|---|
| `.zprofile.thinkpad` | `WM=dwm`, `startx` |
| `.zprofile.pc` | `WM=dwm`, `startx` |
| `.zprofile.hackerman` | `WM=dwm`, `startx` |
| `.zprofile.laptop` | `startx`, i3 workspace refs |
| `.bash_profile.thinkpad` | `setxkbmap`, `startx` |
| `.bash_profile.laptop` | `startx` |
| `.config/sh/shrc` | Aliases for `xrdb`, `sxhkd`, `bspwm`, `i3`, `picom` |

### Input / hardware

| Path | X11-ism | Wayland equivalent |
|---|---|---|
| `scripts/set_kb_map` | `setxkbmap` | `xkb_options` in compositor config or `swaymsg` |
| `scripts/keyboard_set_capslock_to_escape` | `setxkbmap` | compositor config |
| `scripts/watch_keyboard.sh` | `xmodmap` | compositor config / `interception-tools` |
| `user/keyboard-remap.service` | `xmodmap` systemd service | `interception-tools` or compositor config |
| `scripts/Huion610ProTablet.sh` | `xsetwacom` | `swaymsg input` / tablet config in compositor |
| `scripts/toggle_rotation.sh` | `xrandr` | `wlr-randr` or compositor-specific |

### Screen capture / recording

| Path | X11-ism | Wayland equivalent |
|---|---|---|
| `scripts/screenrecord.sh` | `xrandr`, `import`, `x11grab` | `wf-recorder`, `slurp` + `grim` for region |

### Window manipulation

| Path | X11-ism | Wayland equivalent |
|---|---|---|
| `scripts/killx` | `xdotool windowkill` | `swaymsg kill` / compositor-specific |
| `scripts/togglerc` | `xdotool search` + `st` | compositor-specific |

### Shell aliases in `.config/sh/shrc`

| Line | Alias | X11 tool |
|---|---|---|
| 57 | `sxhkdrc` | sxhkd key daemon |
| 58 | `bspwmrc` | bspwm WM |
| 68 | `xres` | xrdb/Xresources |
| 83 | `i3rc` | i3 WM |
| 86 | `i3tag` | i3 WM |
| 88 | `i3sbar` | i3status bar |
| 94 | `picomrc` | picom compositor |
| 202 | `screensave` | `xclip` image extraction |

---

## Package List Updates Needed

**`archlinux_x86_64_packages`** — these X11-only packages can be removed/replaced:

| Line | X11 Package | Wayland Replacement |
|---|---|---|
| 14 | `xdotool` | `ydotool` |
| 28 | `xclip` | `wl-clipboard` |
| 29 | `shotgun` | `grim` |
| 46 | `feh` | `imv` (+ `swaybg` for wallpapers) |
| 58 | `xsel` | `wl-clipboard` |
