#!/bin/sh
bookarmarks="$(dirname "$0")/web_bookmarks.json"
cat "$bookarmarks" | jq | grep -v { | grep -v '}' | sed 's/\"//g; s/,$//g' | dmenu -c -l 30 | awk '{print $2}' | xclip -selection clipboard
 
