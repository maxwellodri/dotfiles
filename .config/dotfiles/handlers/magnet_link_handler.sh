#!/usr/bin/env bash

DOWNLOAD_DIRS=("$HOME/Downloads/torrents/" "$HOME/Videos/torrents/")

if [[ -n $WAYLAND_DISPLAY ]]; then
    dmenu="dmenu-wl"
elif [[ -n $DISPLAY ]]; then
    dmenu="dmenu"
else
    echo "Error: No Wayland or X11 display detected" >&2
    exit 1
fi

pgrep -f transmission-daemon > /dev/null || (transmission-daemon --no-auth && notify-send "Starting transmission daemon...")
daemon_ready=0
for _ in {1..10}; do
    transmission-remote -l > /dev/null 2>&1 && { daemon_ready=1; break; }
    sleep 0.1
done
(( daemon_ready )) || { notify-send "Transmission Daemon not available"; exit 1; }

default_dir=$(transmission-remote -j -si 2>/dev/null | jq -r '.result.download_dir')

menu=("Manual Directory")
is_default=0
for dir in "${DOWNLOAD_DIRS[@]}"; do
    if [[ ${dir%/} == "${default_dir%/}" ]]; then
        dir="$dir (Default Dir)"
        is_default=1
    fi
    menu+=("$dir")
done
if [[ -n $default_dir ]]; then
    (( is_default )) || menu+=("$default_dir (Default Dir)")
else
    menu+=("Default Dir")
fi

selected_dir=$(printf '%s\n' "${menu[@]}" | "$dmenu" -l 30 -c --class "magnet_dir" -p "Download Directory:")

[[ -n $selected_dir ]] || exit 0
selected_dir=${selected_dir% (Default Dir)}

if [[ $selected_dir == "Manual Directory" ]]; then
    temp_file=$(mktemp)
    wezfuzzy "cd '$HOME' && fd --type directory | fzf --prompt='Select directory: ' --ansi --border=rounded --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6ac,pointer:#f5e0dc --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6ac,hl+:#f38ba8 --bind=ctrl-u:preview-page-up,ctrl-d:preview-page-down --cycle > '$temp_file'"
    selected_dir=$(cat "$temp_file")
    rm -f "$temp_file"
    if [[ -n $selected_dir && "$selected_dir" != /* ]]; then
        selected_dir="$HOME/$selected_dir"
    fi
    [[ -n $selected_dir && -d "$selected_dir" ]] || exit 0
fi

dir_args=()
if [[ $selected_dir != "Default Dir" ]]; then
    dir_args=(-w "$selected_dir")
fi

BEFORE_ADD=$(transmission-remote -j -l | jq -r '.result.torrents[].id')
transmission-remote -a --start-paused "$1" "${dir_args[@]}" --torrent-done-script ~/bin/torrdone || { notify-send "Invalid link ⛔ (Not a magnet link?)"; exit; }
AFTER_ADD=$(transmission-remote -j -l | jq -r '.result.torrents[].id')
TORRENT_ID=$(comm -13 <(sort <<< "$BEFORE_ADD") <(sort <<< "$AFTER_ADD"))
if [ -z "$TORRENT_ID" ]; then
    notify-send "Torrent Already Added 😕"
else
    TORRENT_NAME=$(transmission-remote -j -t "$TORRENT_ID" -i | jq -r '.result.torrents[0].name')
    echo "$TORRENT_ID $TORRENT_NAME $1" >> ~/.cache/torrents.log
    notify-send -t 750 "Torrent Added 🏴‍☠️"
fi
