#!/bin/bash
MIME=$(file --mime-type -b "$1")
notify-send "Default Handler" "File: $1\nMIME: $MIME"
