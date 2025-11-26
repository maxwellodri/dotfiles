#!/usr/bin/env bash

layout=$(echo -e "even-horizontal\neven-vertical\nmain-horizontal\nmain-vertical\ntiled" | fzf-tmux -p 40%,30% --prompt="Layout: ")

if [ -n "$layout" ]; then
    tmux select-layout "$layout"
fi
