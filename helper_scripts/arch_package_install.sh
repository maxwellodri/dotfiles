#!/bin/sh

. "$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)/.config/sh/shutil.sh"

# Non-Arch machines (e.g. the donnie NixOS VPS) get their packages elsewhere.
command -v pacman >/dev/null 2>&1 || {
    echo "pacman not found — skipping package install"
    exit 0
}

# Initialize an empty variable to store the packages
packages=""

# Check if the first argument is provided and the file exists
if [ -n "$1" ] && [ -f "archlinux_x86_64_packages.$1" ]; then
    packages="$(grep -o '^[^#]*' "archlinux_x86_64_packages.$1") "
fi

# Add the packages from the main file
packages="$packages$(grep -o '^[^#]*' archlinux_x86_64_packages)"

if sudo -v 2>/dev/null; then
    run_elevated pacman -S --noconfirm --needed $packages
else
    echo "Skipping package install (no root access)"
fi
