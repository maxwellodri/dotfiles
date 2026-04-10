#!/usr/bin/env bash

DOWNLOAD_DIRS=("$HOME/Downloads/torrents/")

if [[ -n $WAYLAND_DISPLAY ]]; then
    dmenu=dmenu-wl
elif [[ -n $DISPLAY ]]; then
    dmenu=dmenu
else
    echo "Error: No Wayland or X11 display detected" >&2
    exit 1
fi

selected_dir=$(printf '%s\n' "Default Dir" "Manual Directory" "${DOWNLOAD_DIRS[@]}" | "$dmenu" -l 30 -c --class "magnet_dir" -p "Download Directory:")

[[ -n $selected_dir ]] || exit 0

if [[ $selected_dir == "Manual Directory" ]]; then
    temp_file=$(mktemp)
    st -g 100x20+2000+720 -c "stfuzzy" -e sh -c "cd '$HOME' && fd --type directory | fzf --prompt='Select directory: ' --ansi --border=rounded --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6ac,pointer:#f5e0dc --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6ac,hl+:#f38ba8 --bind=ctrl-u:preview-page-up,ctrl-d:preview-page-down --cycle > '$temp_file'"
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

pgrep -f transmission-daemon > /dev/null || (transmission-daemon --no-auth && notify-send "Starting transmission daemon...")
BEFORE_ADD=$(transmission-remote -l | awk 'NR>1 {print $1}' | tr -d '*')
transmission-remote -a --start-paused "$1" "${dir_args[@]}" --torrent-done-script ~/bin/torrdone || { notify-send "Invalid link ⛔ (Not a magnet link?)"; exit; }
AFTER_ADD=$(transmission-remote -l | awk 'NR>1 {print $1}' | tr -d '*')
TORRENT_ID=$(diff <(echo "$BEFORE_ADD") <(echo "$AFTER_ADD") | grep '>' | awk '{print $2}')
if [ -z "$TORRENT_ID" ]; then
    notify-send "Torrent Already Added 😕"
else
    TORRENT_NAME=$(transmission-remote -t "$TORRENT_ID" -i | grep -oP 'Name: \K.*')
    echo "$TORRENT_ID $TORRENT_NAME $1" >> ~/.cache/torrents.log
    notify-send -t 750 "Torrent Added 🏴‍☠️"
fi
