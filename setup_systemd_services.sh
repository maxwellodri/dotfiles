#!/bin/bash
if [ -z "$dotfiles" ] || [ "$EUID" -ne 0 ]; then
    echo "Error: Please run the script as root and pass in the \$dotfiles environment variable using the following command:"
    echo "sudo -E dotfiles=\$dotfiles $0"
    exit 1
fi

# Set the source and destination directories
src_dir=$dotfiles/services
dst_dir=/etc/systemd/system

# Check if the destination directory exists
if [ ! -d "$dst_dir" ]; then
  # Create the destination directory with sudo
  sudo mkdir -p "$dst_dir"
fi

# Check if the source directory exists
if [ ! -d "$src_dir" ]; then
  echo "Error: Source directory does not exist."
  exit 1
fi

# Symlink the files in the source directory to the destination directory
for file in "$src_dir"/*; do
  filename=$(basename "$file")
  src="$src_dir/$filename"
  dst="$dst_dir/$filename"

  # Check if the file already exists in the destination directory
  if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
        continue
    else
      echo "Error: File already exists and differs from the file: $dst"
      exit 1
    fi
  fi
  # The file does not exist or is a symlink to a different file, so create a symlink to the correct source file
  cp "$src" "$dst"
done

# Reload the system manager configuration
systemctl daemon-reload

# Start and enable the services
for file in "$src_dir"/*; do
  filename=$(basename "$file")
  echo "Start/Enabling: $filename"
  systemctl start "$filename"
  systemctl enable "$filename"
done
