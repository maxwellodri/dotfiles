#!/bin/bash

# Directory containing the git repos
SOURCE_DIR=~/source

# Define colors for the highlighted repos
highlight_color="\033[1;32m" # Bright green
reset_color="\033[0m"        # Reset to default

# Highlighted repositories
highlighted_repos=("dwm" "slock" "st" "dotfiles" "dmenu")

# Function to check if a repo is in the highlighted list
is_highlighted_repo() {
    for repo in "${highlighted_repos[@]}"; do
        if [[ "$1" == *"$repo"* ]]; then
            return 0
        fi
    done
    return 1
}

# Iterate over all folders in the source directory
for dir in "$SOURCE_DIR"/*; do
    # Skip if it's not a directory
    [ -d "$dir" ] || continue

    # Check if the directory is a Git repository
    if [ -d "$dir/.git" ]; then
        cd "$dir" || continue

        # Extract repo name from the directory path
        repo_name=$(basename "$dir")

        # Apply color if it's a highlighted repo
        if is_highlighted_repo "$repo_name"; then
            prefix="${highlight_color}"
            suffix="${reset_color}"
        else
            prefix=""
            suffix=""
        fi

        # Check for uncommitted changes
        if ! git diff --quiet || ! git diff --cached --quiet; then
            echo -e "${prefix}Uncommitted changes found in $dir${suffix}"
        fi

        # Check if the repository has an upstream configured
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)

        if [ -z "$UPSTREAM" ]; then
            # No upstream branch configured, so we skip this repo
            continue
        fi

        # Check if there are changes that need to be pushed
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})
        BASE=$(git merge-base @ @{u})

        if [ "$LOCAL" != "$REMOTE" ]; then
            if [ "$LOCAL" = "$BASE" ]; then
                echo -e "${prefix}Repository in $dir needs to pull changes.${suffix}"
            elif [ "$REMOTE" = "$BASE" ]; then
                echo -e "${prefix}Repository in $dir has changes to push.${suffix}"
            else
                echo -e "${prefix}Repository in $dir has diverged.${suffix}"
            fi
        fi
    fi
done
