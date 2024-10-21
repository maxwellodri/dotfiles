#!/bin/bash

handle_magnet_link() {
    pgrep -f transmission-daemon > /dev/null || (transmission-daemon --no-auth && notify-send "Starting transmission daemon...")
    BEFORE_ADD=$(transmission-remote -l | awk 'NR>1 {print $1}' | tr -d '*')
    transmission-remote -a "$1" --torrent-done-script ~/bin/torrdone || { notify-send "Invalid link ⛔ (Not a magnet link?)"; exit; }
    AFTER_ADD=$(transmission-remote -l | awk 'NR>1 {print $1}' | tr -d '*')
    TORRENT_ID=$(diff <(echo "$BEFORE_ADD") <(echo "$AFTER_ADD") | grep '>' | awk '{print $2}')
    if [ -z "$TORRENT_ID" ]; then
        notify-send "Torrent Already Added 😕"
    else
        TORRENT_NAME=$(transmission-remote -t "$TORRENT_ID" -i | grep -oP 'Name: \K.*')
        echo "$TORRENT_ID $TORRENT_NAME $1" >> ~/.cache/torrents.log
        notify-send -t 750 "Torrent Added 🏴‍☠️"
    fi
}

handle_url() {
    CHOICE=$(echo -e "Open in Firefox (new tab)\nOpen in Firefox (default)\nDownload with yt-dlp" | dmenu -i -p "Choose how to open URL:")

    case "$CHOICE" in
        "Open in Firefox (default)")
            firefox "$1" &
            ;;
        "Open in Firefox (new tab)")
            firefox --new-tab "$1" &
            ;;

        "Download with yt-dlp")
            yt-dlp --restrict-filenames --abort-on-unavailable-fragment --trim-filenames 225 -o "~/Downloads/ytdlp/%(title)s.%(ext)s" "$1"
            ;;
        *)
            notify-send "No valid option selected (url)."
            ;;
    esac
}

handle_directory() {
    CHOICE=$(echo -e "Open in st\nOpen in pcmanfm" | dmenu -i -p "Choose how to open directory:")

    case "$CHOICE" in
        "Open in st")
            st -d "$1" &
            ;;
        "Open in pcmanfm")
            pcmanfm "$1" &
            ;;
        *)
            notify-send "No valid option selected (directory)."
            ;;
    esac
}

handle_file() {
    CHOICE=$(echo -e "Open parent directory in st\nOpen parent directory in pcmanfm\nOpen file with xdg-open" | dmenu -i -p "Choose how to handle file:")

    case "$CHOICE" in
        "Open parent directory in st")
            st -d "$(dirname "$1")" &
            ;;
        "Open parent directory in pcmanfm")
            pcmanfm "$(dirname "$1")" &
            ;;
        "Open file with xdg-open")
            xdg-open "$1" &
            ;;
        *)
            notify-send "No valid option selected."
            ;;
    esac
}

if [ $# -eq 0 ]; then
    # No command-line arguments, read from clipboard
    input=$(xclip -o -selection clipboard | sed 's/^[ \t]*//;s/[ \t]*$//')
else
    # Concatenate command-line arguments and trim whitespace
    input=$(echo "$*" | sed 's/^[ \t]*//;s/[ \t]*$//')
fi

parsed_input=$(echo "$input" | grep -oP '<[^>]+src="[^"]+"[^>]*>' | sed -e 's/.*src="//' -e 's/"[^>]*>//')
if echo "$input" | grep -Eo 'https?://[^ ]+' > /dev/null; then
    handle_url "$input"  
elif echo "$input" | grep -Eo 'magnet:\?[^ ]+' > /dev/null; then
    handle_magnet_link "$input"
elif [ ! -z "$parsed_input" ] && command -v _handle_curl_req > /dev/null; then
    echo "$parsed_input"
    _handle_curl_req "$parsed_input"
elif [ -f "$input" ]; then
    handle_file "$input"
elif [ -d "$input" ]; then
    handle_directory "$input"
else
    notify-send "Unknown Input" "Input is not recognized: $input"
fi
