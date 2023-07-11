#!/bin/bash

# Get the list of torrents and their statuses using transmission-remote
torrent_list="$(transmission-remote -l | tail -n +2 | head -n -2)"

# Loop through each line of the torrent list
while read -r line; do
  # Extract the torrent ID and progress from the line
  torrent_id="$(echo "$line" | cut -d' ' -f1 | cut -d'*' -f1)"
  progress="$(echo "$line" | awk '{print $2}')"
  torrent_name="$(echo "$line" | awk '{print $NF}')"

  # If the progress is not 100%, print the line to the terminal
  if [ "$progress" != "100%" ]; then
    echo "Leaving $line"
  # If the progress is 100%, remove the torrent
  else
    echo "Removing torrent $torrent_name..."
    transmission-remote -t "$torrent_id" -r
  fi
done <<< "$torrent_list"
