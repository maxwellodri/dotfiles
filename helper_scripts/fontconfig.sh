#!/bin/sh
############################
# This script sets up fontconfig and rebuilds font cache
############################

dir="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)"
font=".config/fontconfig/fonts.conf"

echo "Setting up fontconfig..."

parent="$(dirname "$font")"
mkdir -p "$HOME/$parent"

dest="$HOME/$font"
if [ -e "$dest" ]; then
    echo "Moving existing $font to temp directory"
    tmpdir=$(mktemp -d)
    mv "$dest" "$tmpdir"
fi

ln -sf "$dir/$font" "$HOME/$font"
echo "Created symlink for $font"

echo "Rebuilding font cache..."
fc-cache -fv

echo "Font setup complete."
