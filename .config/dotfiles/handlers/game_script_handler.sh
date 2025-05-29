#!/usr/bin/env bash
file="$1"

if [[ -x "$file" ]] && file --mime-type -b "$file" | grep -q "text/x-shellscript"; then
    exec "$file"
else
    exec "${EDITOR:-nvim}" "$file"
fi
