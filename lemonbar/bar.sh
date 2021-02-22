#!/bin/sh

# Import the colors
. "${HOME}/.cache/wal/colors.sh"

python3 $dotfiles/lemonbar/main.py | lemonbar -B "$color2" -F "$color8" -p # Other flags here.
