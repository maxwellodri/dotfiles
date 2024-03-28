#!/bin/bash
# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script as root."
    exit 1
fi

# Change to the directory where the script is located
cd "$(dirname "$0")"

# Check if the required directories exist
if [ ! -d "udev-rules" ] || [ ! -d "systemd-services" ]; then
    echo "Error: Required directories 'udev-rules' and 'systemd-services' do not exist."
    exit 1
fi

# Function to handle copying of files
copy_files() {
    local src_dir="$1"
    local dst_dir="$2"

    # Ensure the destination directory exists
    mkdir -p "$dst_dir"

    # Iterate through the files in the source directory
    for src in "$src_dir"/*; do
        local filename=$(basename "$src")
        local dst="$dst_dir/$filename"

        # Check if the destination file exists
        if [ -e "$dst" ]; then
            # If contents are the same, continue
            if cmp -s "$src" "$dst"; then
                echo "Skipping $src: File is identical."
                continue
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
    done
}

# Copy udev rules and systemd services
copy_files "udev-rules" "/etc/udev/rules.d"
copy_files "systemd-services" "/etc/systemd/system"

# Reload the system manager configuration
systemctl daemon-reload

# Output success message
echo "Configuration applied successfully!"
