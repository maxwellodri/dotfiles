#!/bin/bash

SHRC_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sh/shrc"

if [[ ! -f "$SHRC_FILE" ]]; then
    exit 1
fi

# shellcheck source=/dev/null
source "$SHRC_FILE"

if [[ -z "$bin" ]]; then
    exit 1
fi

exec "$bin/sw" start
