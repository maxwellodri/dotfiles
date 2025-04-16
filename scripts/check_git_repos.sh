#!/bin/bash

SOURCE_DIR=$SOURCE

highlight_color="\033[1;32m" # Bright green
reset_color="\033[0m"        # Reset to default

highlighted_repos=("dwm" "slock" "st" "dotfiles" "dmenu" "private")

is_highlighted_repo() {
    for repo in "${highlighted_repos[@]}"; do
        if [[ "$1" == *"$repo"* ]]; then
            return 0
        fi
    done
    return 1
}

for dir in "$SOURCE_DIR"/*; do
    [ -d "$dir" ] || continue

    if [ -d "$dir/.git" ]; then
        cd "$dir" || continue

        repo_name=$(basename "$dir")

        if is_highlighted_repo "$repo_name"; then
            prefix="${highlight_color}"
            suffix="${reset_color}"
            git fetch
        else
            prefix=""
            suffix=""
        fi

        # Initialize message variables
        message=""

        # Check for uncommitted changes
        if ! git diff --quiet || ! git diff --cached --quiet; then
            message="Uncommitted changes"
        fi

        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)

        if [ -n "$UPSTREAM" ]; then
            LOCAL=$(git rev-parse @)
            REMOTE=$(git rev-parse @{u})
            BASE=$(git merge-base @ @{u})

            if [ "$LOCAL" != "$REMOTE" ]; then
                if [ "$LOCAL" = "$BASE" ]; then
                    if [ -n "$message" ]; then
                        message+=", "
                    fi
                    message+="needs to pull changes"
                elif [ "$REMOTE" = "$BASE" ]; then
                    if [ -n "$message" ]; then
                        message+=", "
                    fi
                    message+="has changes to push"
                else
                    if [ -n "$message" ]; then
                        message+=", "
                    fi
                    message+="has diverged"
                fi
            fi
        fi

        # Only print the message if there's something to report
        if [ -n "$message" ]; then
            echo -e "${prefix}Repository in $dir: $message.${suffix}"
        fi
    fi
done
