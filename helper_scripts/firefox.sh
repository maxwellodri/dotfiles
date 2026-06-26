#!/bin/bash

REPO_ROOT="$(git -C "$(dirname "$(realpath "$0")")" rev-parse --show-toplevel)"
profiles_ini="$HOME/.mozilla/firefox/profiles.ini"
user_js_path="$REPO_ROOT/firefox/user.js"
user_chrome_css_path="$REPO_ROOT/firefox/userChrome.css"
user_content_css_path="$REPO_ROOT/firefox/userContent.css"
backup_dir=$(mktemp -d)

if [ ! -f "$user_js_path" ]; then
    echo "Error: $user_js_path does not exist."
    exit 1
fi

if [ ! -f "$user_chrome_css_path" ]; then
    echo "Error: $user_chrome_css_path does not exist."
    exit 1
fi

if [ ! -f "$user_content_css_path" ]; then
    echo "Error: $user_content_css_path does not exist."
    exit 1
fi

# Extract the default profile path. Prefer the [Install...] section's Default=
# value (the profile Firefox actually boots into); fall back to the profile
# marked Default=1 if no install section exists.
default_profile=$(awk -F= '
/^\[Install/ {in_install=1; next}
/^\[/        {in_install=0}
in_install && /^Default=/ {install=$2}
/^Default=1$/ {default_flag=1}
/^Path=/ && default_flag {profile=$2; default_flag=0}
END {print (install ? install : profile)}
' "$profiles_ini")

# Check if we found a default profile
if [ -n "$default_profile" ]; then
    profile_path="$HOME/.mozilla/firefox/$default_profile"
    profile_user_js="$profile_path/user.js"
    profile_chrome_dir="$profile_path/chrome"
    profile_user_chrome_css="$profile_chrome_dir/userChrome.css"
    profile_user_content_css="$profile_chrome_dir/userContent.css"
    echo "Default profile path: $profile_path"

    # Handle existing user.js
    if [ -L "$profile_user_js" ]; then
        if [ "$(readlink -- "$profile_user_js")" == "$user_js_path" ]; then
            echo "user.js is already linked correctly."
        else
            echo "user.js is a symlink, but not pointing to $user_js_path. Replacing it."
            rm "$profile_user_js"
        fi
    elif [ -f "$profile_user_js" ]; then
        echo "user.js exists and is not a symlink. Backing it up to $backup_dir."
        mkdir -p "$backup_dir"
        mv "$profile_user_js" "$backup_dir/user.js"
        echo "Backup created at $backup_dir/user.js"
    fi
    ln -sf "$user_js_path" "$profile_user_js"
    echo "user.js linked to $profile_user_js"

    # Handle existing userChrome.css
    mkdir -p "$profile_chrome_dir"
    if [ -L "$profile_user_chrome_css" ]; then
        if [ "$(readlink -- "$profile_user_chrome_css")" == "$user_chrome_css_path" ]; then
            echo "userChrome.css is already linked correctly."
        else
            echo "userChrome.css is a symlink, but not pointing to $user_chrome_css_path. Replacing it."
            rm "$profile_user_chrome_css"
        fi
    elif [ -f "$profile_user_chrome_css" ]; then
        echo "userChrome.css exists and is not a symlink. Backing it up to $backup_dir."
        mv "$profile_user_chrome_css" "$backup_dir/userChrome.css"
        echo "Backup created at $backup_dir/userChrome.css"
    fi

    ln -sf "$user_chrome_css_path" "$profile_user_chrome_css"
    echo "userChrome.css linked to $profile_user_chrome_css"

    if [ -L "$profile_user_content_css" ]; then
        if [ "$(readlink -- "$profile_user_content_css")" == "$user_content_css_path" ]; then
            echo "userContent.css is already linked correctly."
        else
            echo "userContent.css is a symlink, but not pointing to $user_content_css_path. Replacing it."
            rm "$profile_user_content_css"
        fi
    elif [ -f "$profile_user_content_css" ]; then
        echo "userContent.css exists and is not a symlink. Backing it up to $backup_dir."
        mv "$profile_user_content_css" "$backup_dir/userContent.css"
        echo "Backup created at $backup_dir/userContent.css"
    fi

    ln -sf "$user_content_css_path" "$profile_user_content_css"
    echo "userContent.css linked to $profile_user_content_css"
else
    echo "No default profile found."
    exit 1
fi
