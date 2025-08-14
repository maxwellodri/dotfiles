#!/usr/bin/env bash

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
