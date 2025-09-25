#!/bin/bash
if [ -z "$bin" ]; then
    notify-send "Error" "\$bin environment variable not set"
    exit 1
fi

temp_file="/tmp/dwm_selection_$(date +%s)"
xclip -selection primary -o > "$temp_file" 2>/dev/null
echo "DISPLAY=\"$DISPLAY\" \"$bin/text_handler\" file \"$temp_file\" > /tmp/dotfiles/dwm_texthandler_debug.log 2>&1; rm \"$temp_file\"" | at now
