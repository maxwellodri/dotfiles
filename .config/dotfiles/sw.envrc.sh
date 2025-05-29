#!/bin/bash

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/sw.yaml"
CURRENT_PATH=$(realpath "$PWD")

PROJECT_NAME=$(yq eval ".projects[] | select(.path == \"$CURRENT_PATH\") | .name" "$CONFIG_FILE" 2>/dev/null)

if [[ -z "$PROJECT_NAME" ]]; then
    echo "Warning: Directory not in projects config - run 'sw add' to track this project" >&2
    return
fi

if tmux has-session -t "$PROJECT_NAME" 2>/dev/null; then
    tmux attach-session -t "$PROJECT_NAME"
else
    tmux new-session -d -s "$PROJECT_NAME" -c "$PWD"
    tmux attach-session -t "$PROJECT_NAME"
fi
