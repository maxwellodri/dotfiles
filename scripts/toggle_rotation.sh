#!/bin/bash

# Get the primary monitor name
PRIMARY_MONITOR=$(xrandr --query | grep " connected primary" | cut -d' ' -f1)

if [ -z "$PRIMARY_MONITOR" ]; then
    # If no primary monitor found, get the first connected monitor
    PRIMARY_MONITOR=$(xrandr --query | grep " connected" | head -n1 | cut -d' ' -f1)
fi

if [ -z "$PRIMARY_MONITOR" ]; then
    echo "Error: No connected monitor found"
    exit 1
fi

# Get current rotation from the position info line
CURRENT_ROTATION=$(xrandr --query | grep "$PRIMARY_MONITOR connected" | grep -oE "(normal|left|right|inverted)" | head -n1)

case "$CURRENT_ROTATION" in
    "normal")
        echo "Rotating $PRIMARY_MONITOR to vertical (left)"
        xrandr --output "$PRIMARY_MONITOR" --rotate left
        ;;
    "left")
        echo "Rotating $PRIMARY_MONITOR to horizontal (normal)"
        xrandr --output "$PRIMARY_MONITOR" --rotate normal
        ;;
    *)
        echo "Current rotation: $CURRENT_ROTATION"
        echo "Setting $PRIMARY_MONITOR to horizontal (normal)"
        xrandr --output "$PRIMARY_MONITOR" --rotate normal
        ;;
esac
[ -n "$bin" ] && [ -x "$bin/background_set.sh" ] && "$bin/background_set.sh"

