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
active=$(remind ~/.config/remind/reminders.rem | tail -n +2 | grep -v '^$')

if [ "$action" = "count" ]; then
    echo "$active" | wc -l
elif [ "$action" = "list" ]; then
    tmp="/tmp/remind/active_reminders"
    mkdir /tmp/remind/ 2>/dev/null
    echo "$active" > "$tmp"
    neovide "$tmp"
    rm "$tmp"
fi
