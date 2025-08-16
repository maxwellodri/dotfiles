#!/bin/sh
#setsid -f st -d "$(sw --path -g)" >/dev/null 2>&1

project_path=$(sw --path -g)
[ -z "$project_path" ] && exit 0

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/sw.yaml"
on_enter_cmd=$(yq eval ".projects | to_entries | map(select(.value.path == \"$project_path\")) | .[0].value.on_enter" "$config_file" 2>/dev/null)

if [ -n "$on_enter_cmd" ] && [ "$on_enter_cmd" != "null" ]; then
    setsid -f st -d "$project_path" -e sh -c "cd '$project_path' && $on_enter_cmd; exec \$SHELL" >/dev/null 2>&1
else
    setsid -f st -d "$project_path" >/dev/null 2>&1
fi
