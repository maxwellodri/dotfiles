#!/usr/bin/env bash

# Determine cache directory
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
bevy_cache_dir="$cache_dir/bevy"
bevy_crates_file="$bevy_cache_dir/bevy_crates"

# Create cache directory if it doesn't exist
mkdir -p "$bevy_cache_dir"

# Fetch bevy crates from GitHub API
response=$(curl -s https://api.github.com/repos/bevyengine/bevy/contents/crates 2>/dev/null)

# Check if we got a valid response
if [ -z "$response" ] || echo "$response" | grep -q "API rate limit exceeded"; then
    exit 0
fi

# Extract crate names and write to file
echo "$response" | grep '"name":' | sed 's/.*"name": "\(.*\)".*/\1/' > "$bevy_crates_file"

# Verify we wrote something
if [ ! -s "$bevy_crates_file" ]; then
    rm -f "$bevy_crates_file"
    exit 0
fi
