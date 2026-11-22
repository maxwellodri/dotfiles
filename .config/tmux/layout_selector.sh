#!/usr/bin/env bash
# $1 = invoking window id (passed by binding): run-shell children have no
# client context, so implicit targets would resolve to an arbitrary session
w="${1:?usage: layout_selector.sh <window_id>}"

layout=$(echo -e "even-horizontal\neven-vertical\nmain-horizontal\nmain-vertical\ntiled" | fzf-tmux -p 40%,30% --prompt="Layout: ")

if [ -n "$layout" ]; then
    tmux select-layout -t "$w" "$layout"
fi
