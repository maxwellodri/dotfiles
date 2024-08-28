#!/bin/bash

# Variables
OUTPUT_DIR="$HOME/Videos"
FILENAME="screencast_$(date +%Y-%m-%d_%H-%M-%S).mp4"
FULL_PATH="$OUTPUT_DIR/$FILENAME"
SCREENSHOT_FILE="/tmp/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Get primary monitor resolution and offset
PRIMARY_MONITOR_INFO=$(xrandr | grep "primary" | awk '{print $4}')
PRIMARY_MONITOR_RESOLUTION=$(echo $PRIMARY_MONITOR_INFO | cut -d'+' -f1)
PRIMARY_MONITOR_OFFSET_X=$(echo $PRIMARY_MONITOR_INFO | cut -d'+' -f2)
PRIMARY_MONITOR_OFFSET_Y=$(echo $PRIMARY_MONITOR_INFO | cut -d'+' -f3)

# Check if --test flag is passed
if [ "$1" == "--test" ]; then
    # Take a screenshot of the primary monitor
    import -window root -crop "$PRIMARY_MONITOR_RESOLUTION+$PRIMARY_MONITOR_OFFSET_X+$PRIMARY_MONITOR_OFFSET_Y" "$SCREENSHOT_FILE"
    
    # Open the screenshot with feh
    feh "$SCREENSHOT_FILE"
    
    # Exit after testing
    exit 0
fi

# Start screen recording on the primary monitor
ffmpeg -video_size "$PRIMARY_MONITOR_RESOLUTION" -framerate 30 -f x11grab -i $DISPLAY+$PRIMARY_MONITOR_OFFSET_X,$PRIMARY_MONITOR_OFFSET_Y -f pulse -ac 2 -i default "$FULL_PATH"
