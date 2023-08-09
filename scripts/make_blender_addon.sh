#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <python_file>"
    exit 1
fi

python_file="$1"
addon_name=$(basename "$python_file" .py)
addon_dir="$addon_name"_addon

mkdir -p "$addon_dir"
cp "$python_file" "$addon_dir"/__init__.py

zip -r "$addon_name".zip "$addon_dir"
rm -r "$addon_dir"

echo "Addon packaged as $addon_name.zip"
