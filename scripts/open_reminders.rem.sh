#!/bin/sh
reminders_file="$HOME/.config/remind/reminders.rem"
[ -f "$reminders_file" ] && { st -f "Fira Code :pixelsize=16:antialias=true:autohint=true" -e nvim "$reminders_file" ; true; } || notify-send "No reminders.rem file at $reminders_file"


