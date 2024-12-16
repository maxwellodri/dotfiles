#!/bin/bash

# Check if at least one argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <torrent_id1> [torrent_id2 ...]"
    exit 1
fi

# Function to process a single torrent
process_torrent() {
    local torrent_id=$1
    
    # Get magnet link before removing
    echo "Getting magnet link for torrent ID $torrent_id..."
    magnet_link=$(transmission-remote -t $torrent_id -i | grep "Magnet:" | sed 's/.*: //')
    
    if [ -z "$magnet_link" ]; then
        echo "Failed to get magnet link for torrent ID $torrent_id"
        return 1
    fi
    
    # Save magnet link to a file named with the torrent ID
    echo "$magnet_link" > "magnet_${torrent_id}.txt"
    echo "Saved magnet link to magnet_${torrent_id}.txt"
    
    # Remove the torrent
    echo "Removing torrent ID $torrent_id..."
    transmission-remote -t $torrent_id --remove
    
    # Re-add the torrent
    echo "Re-adding torrent..."
    transmission-remote -a "$magnet_link"
    
    echo "Processed torrent ID $torrent_id"
    echo "------------------------"
}

# Process each torrent ID provided as argument
for torrent_id in "$@"; do
    if ! [[ "$torrent_id" =~ ^[0-9]+$ ]]; then
        echo "Error: '$torrent_id' is not a valid torrent ID"
        continue
    fi
    process_torrent "$torrent_id"
done
