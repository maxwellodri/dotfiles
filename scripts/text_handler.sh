#!/bin/bash

#notify-send "$@"

handle_magnet_link() {
    pgrep -f transmission-daemon > /dev/null || (transmission-daemon --no-auth && notify-send "Starting transmission daemon...")
    BEFORE_ADD=$(transmission-remote -l | awk 'NR>1 {print $1}' | tr -d '*')
    transmission-remote -a --start-paused "$1" --torrent-done-script ~/bin/torrdone || { notify-send "Invalid link ⛔ (Not a magnet link?)"; exit; }
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
    CHOICE=$(echo -e "Open in Firefox Tab\nOpen in New Firefox Window\nDownload with yt-dlp using tsp (tsp_ytdlp)\nDownload with gallery-dl\nAdd as feed\nWatch as video in mpv" | dmenu -l 20 -c -i -p "Choose how to open URL:")

    case "$CHOICE" in
        "Open in New Firefox Window")
            firefox --new-window "$1" &
            ;;
        "Open in Firefox Tab")
            firefox --new-tab "$1" &
            ;;
        "Download with yt-dlp using tsp (tsp_ytdlp)")
            #stcmd "yt-dlp --restrict-filenames --abort-on-unavailable-fragment --trim-filenames 225 -o '~/Downloads/ytdlp/%(title)s.%(ext)s' \"$1\""
            tsp_ytdlp "$1"
            ;;
        "Download with gallery-dl")
            stcmd "gallery-dl $1"
            ;;
        "Add as feed")
            handle_feed "$1"
            ;;
        "Watch as video in mpv")
            stcmd "mpv $1"
            ;;
        *)
            notify-send "No valid option selected (url)."
            ;;
    esac
}

handle_feed() {
    local url="$1"
    local line_num=""
    line_num=$(grep -F -n "$url" ~/.config/newsboat/urls | cut -d':' -f1)
    if [ -n "$line_num" ]; then
        notify-send "Feed already exists in newsboat: $url" "Found on line $line_num"
        return 0
    fi
    if curl -s "$url" | grep -E "<rss|<feed" > /dev/null; then

        echo "$url" >> ~/.config/newsboat/urls
        notify-send "Added feed to newsboat: $url"
        return 0
    else
        notify-send "Error URL does not appear to be a valid RSS/Atom feed: $url"
        return 1
    fi
}

handle_directory() {
    CHOICE=$(echo -e "Open in st\nOpen in pcmanfm" | dmenu -l 20 -c -i -p "Choose how to open directory:")

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
    CHOICE=$(echo -e "Open parent directory in st\nOpen parent directory in pcmanfm\nOpen file with xdg-open" | dmenu -l 20 -c -i -p "Choose how to handle file:")

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
if echo "$input" | grep -Eo "https://(www\.reddit\.com/.+\.rss|www\.youtube\.com/feeds/videos\.xml\?channel_id=.+)" > /dev/null; then
    handle_feed "$input"
elif echo "$input" | grep -Eo 'https?://[^ ]+' > /dev/null; then
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
