#!/bin/sh

# Initialize an empty variable to store the packages
packages=""

# Check if the first argument is provided and the file exists
if [ -n "$1" ] && [ -f "archlinux_x86_64_packages.$1" ]; then
    packages="$(grep -o '^[^#]*' "archlinux_x86_64_packages.$1") "
fi

# Add the packages from the main file
packages="$packages$(grep -o '^[^#]*' archlinux_x86_64_packages)"

# Install all the combined packages
echo "$packages" | xargs sudo pacman -S --noconfirm --needed
