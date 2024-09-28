#!/bin/sh

# Default action is 'list'
action="list"

# Parse arguments
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [--count | --list]"
    exit 1
elif [ "$#" -eq 1 ]; then
    case "$1" in
        --count)
            action="count"
            ;;
        --list)
            action="list"
            ;;
        *)
            echo "Invalid option: $1"
            echo "Usage: $0 [--count | --list]"
            exit 1
            ;;
    esac
fi

# Get active reminders
active=$(remind -t5 ~/.config/remind/reminders.rem | tail -n +2 | grep -v '^$')

if [ "$action" = "count" ]; then
    # Output the count of active reminders
    echo "$active" | wc -l
elif [ "$action" = "list" ]; then
    # Create a temporary file
    tmp="/tmp/remind/active_reminders"
    # Send a notification (optional)
    notify-send "hello there! $tmp"
    mkdir /tmp/remind/
    echo "$active" > "$tmp"
    # Open the file with neovide
    neovide "$tmp"
    rm "$tmp"
fi