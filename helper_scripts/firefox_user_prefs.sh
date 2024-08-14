#!/bin/bash

# Path to the profiles.ini file
profiles_ini="$HOME/.mozilla/firefox/profiles.ini"

# Path to the user.js file
user_js_path="$PWD/helper_scripts/user.js"

# Directory for backups
backup_dir="$HOME/.dotfiles_old"

# Check if user.js file exists
if [ ! -f "$user_js_path" ]; then
    echo "Error: $user_js_path does not exist."
    exit 1
fi

# Extract the profile path associated with Default=1
default_profile=$(awk -F= '
  BEGIN {profile=""; default_found=0}
  /^Default=1$/ {default_found=1}
  /^Path=/ && default_found {profile=$2; default_found=0}
  END {print profile}
' "$profiles_ini")

# Check if we found a default profile
if [ -n "$default_profile" ]; then
    profile_path="$HOME/.mozilla/firefox/$default_profile"
    profile_user_js="$profile_path/user.js"
    echo "Default profile path: $profile_path"
    
    # Handle existing user.js
    if [ -L "$profile_user_js" ]; then
        if [ "$(readlink -- "$profile_user_js")" == "$user_js_path" ]; then
            echo "user.js is already linked correctly."
            exit 0
        else
            echo "user.js is a symlink, but not pointing to $user_js_path. Replacing it."
            rm "$profile_user_js"
        fi
    elif [ -f "$profile_user_js" ]; then
        echo "user.js exists and is not a symlink. Backing it up."
        mkdir -p "$backup_dir"
        mv "$profile_user_js" "$backup_dir/user.js"
        echo "Backup created at $backup_dir/user.js"
    fi
    
    # Link the user.js file to the profile directory
    ln -s "$user_js_path" "$profile_user_js"
    echo "user.js linked to $profile_user_js"
else
    echo "No default profile found."
    exit 1
fi
