#!/bin/sh
session=$(tmux display-message -p "#{session_id}")
current_title=$(tmux display-message -p "#{pane_title}")
non_terminal=$(tmux list-panes -s -t "$session" -F "#{pane_title}" | grep -v "^terminal$" | wc -l)

if [ "$current_title" != "terminal" ] && [ "$non_terminal" -gt 1 ]; then
    new_window=$(tmux break-pane -P -F "#{window_id}")
    tmux select-window -t "$new_window"
fi
