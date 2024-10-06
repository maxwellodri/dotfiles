#!/bin/bash
# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root."
    exit 1
fi

# Change to the directory where the script is located
cd "$(dirname "$0")"
[ -f "$PWD/.dotfile_tag" ] || (echo "No $PWD/.dotfile_tag found. Make sure to run ./installer_main.sh -> helper_scripts/makesymlinks.sh before this!" && exit)
echo "Copying $PWD/.dotfile_tag to /etc/dotfile_tag"
cp "$PWD/.dotfile_tag" "/etc/dotfile_tag"

# Check if the required directories exist
if [ ! -d "udev-rules" ] || [ ! -d "systemd-services" ] || [ ! -d "system_configs" ]; then
    echo "Error: Required directories 'udev-rules', 'systemd-services', and 'system_configs' do not exist."
    exit 1
fi

# Function to handle copying of files
copy_files() {
    local src="$1"
    local dst_dir="$2"

    # Ensure the destination directory exists
    mkdir -p "$dst_dir"

    # Check if the source is a file
    if [ -f "$src" ]; then
        local filename=$(basename "$src")
        local dst="$dst_dir/$filename"

        # Check if the destination file exists
        if [ -e "$dst" ]; then
            # If contents are the same, continue
            if cmp -s "$src" "$dst"; then
                echo "Skipping $src: File is identical."
                return 0
            fi

            # If source is newer, copy it over
            if [ "$src" -nt "$dst" ]; then
                cp "$src" "$dst"
                chmod 644 "$dst"
                echo "Updated: $dst"
            else
                dst_date_modified=$(date -r "$dst" +"%Y-%m-%d %H:%M:%S")
                src_date_modified=$(date -r "$src" +"%Y-%m-%d %H:%M:%S")
                echo "Error: Destination file $dst is newer than the source file."
                echo "($dst_date_modified > $src_date_modified)"
                exit 1
            fi
        else
            # Destination file does not exist, so copy source file
            cp "$src" "$dst"
            chmod 644 "$dst"
            echo "Copied $src to $dst"
        fi
        return 0
    fi

    # If the source is a directory, iterate through the files
    if [ -d "$src" ]; then
        for file in "$src"/*; do
            copy_files "$file" "$dst_dir"
        done
    fi
}

# Copy udev rules and systemd services
copy_files "udev-rules" "/etc/udev/rules.d"
copy_files "systemd-services" "/etc/systemd/system"

# Handle individual files in system_configs/etc
copy_files "system_configs/etc/tlp.conf" "/etc"
copy_files "system_configs/etc/pacman.d/hooks" "/etc/pacman.d/hooks"

# Reload the system manager configuration
systemctl daemon-reload

# Output success message
echo "Configuration applied successfully!"
