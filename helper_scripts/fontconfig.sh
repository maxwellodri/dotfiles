#!/bin/sh
############################
# This script sets up fontconfig and rebuilds font cache
############################

dir="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)"
font=".config/fontconfig/fonts.conf"
dest="$HOME/$font"

if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$dir/$font" ]; then
    echo "Font config already linked, skipping."
    exit 0
fi

echo "Setting up fontconfig..."

parent="$(dirname "$font")"
mkdir -p "$HOME/$parent"

if [ -e "$dest" ]; then
    echo "Moving existing $font to temp directory"
    tmpdir=$(mktemp -d)
    mv "$dest" "$tmpdir"
fi

ln -sf "$dir/$font" "$dest"
echo "Created symlink for $font"

echo "Rebuilding font cache..."
fc-cache -f

echo "Font setup complete."
