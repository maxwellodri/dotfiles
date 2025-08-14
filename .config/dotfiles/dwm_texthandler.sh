#!/bin/bash

if [ -z "$bin" ]; then
    notify-send "Error" "\$bin environment variable not set"
    exit 1
fi

selection=$(xclip -selection primary -o 2>/dev/null)
echo "DISPLAY=\"$DISPLAY\" \"$bin/text_handler\" \"$selection\" > /tmp/dotfiles/dwm_texthandler_debug.log 2>&1" | at now
