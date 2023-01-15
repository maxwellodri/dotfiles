#!/bin/bash

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
    # Check if the file is a symlink to the source file
    if [ "$(readlink "$dst")" = "$src" ]; then
      # The file is already a symlink to the correct source file, so do nothing
      continue
    else
      # The file already exists and is not a symlink to the correct source file, so exit with an error message
      echo "Error: File already exists and is not a symlink to the correct source file: $dst"
      exit 1
    fi
  fi

  # The file does not exist or is a symlink to a different file, so create a symlink to the correct source file
  ln -s "$src" "$dst"
done

# Reload the system manager configuration
systemctl daemon-reload

# Start and enable the services
for file in "$src_dir"/*; do
  filename=$(basename "$file")
  service_name="${filename%.*}"
  systemctl start "$service_name"
  systemctl enable "$service_name"
done
