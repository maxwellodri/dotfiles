#!/bin/sh
reminders_file="$HOME/.config/remind/reminders.rem" 
[ -f "$reminders_file" ] && { neovide "$reminders_file"; true; } || notify-send "No reminders.rem file at $reminders_file"
