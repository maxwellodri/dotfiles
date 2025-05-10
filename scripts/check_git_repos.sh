#!/bin/bash
highlight_color="\033[1;32m" # Bright green
giga_highlight_color="\033[1;35m" # Bright magenta (pink)
reset_color="\033[0m"        # Reset to default
important_repos=("dwm" "slock" "st" "dotfiles" "dmenu")
giga_important_repos=("private" ".password-store")
is_important_repo() {
    for repo in "${important_repos[@]}"; do
        if [[ "$1" == "$repo" ]]; then
            return 0
        fi
    done
    return 1
}
is_giga_important_repo() {
    for repo in "${giga_important_repos[@]}"; do
        if [[ "$1" == "$repo" ]]; then
            return 0
        fi
    done
    return 1
}
check_git_repo() {
    local dir="$1"
    if [ -d "$dir/.git" ]; then
        cd "$dir" || return
        local repo_name=""
        repo_name=$(basename "$dir")
        local prefix=""
        local suffix=""
        if is_giga_important_repo "$repo_name"; then
            prefix="${giga_highlight_color}"
            suffix="${reset_color}"
            git fetch
        elif is_important_repo "$repo_name"; then
            prefix="${highlight_color}"
            suffix="${reset_color}"
            git fetch
        fi

        # Initialize message variables
        local message=""

        # Check for uncommitted changes
        if [ -n "$(git status --porcelain)" ]; then
            message="Uncommitted changes"
        fi

        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
        if [ -n "$UPSTREAM" ]; then
            LOCAL=$(git rev-parse @)
            REMOTE=$(git rev-parse '@{u}')
            BASE=$(git merge-base @ '@{u}')
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
}
for dir in "$SOURCE"/*; do
    [ -d "$dir" ] || continue
    check_git_repo "$dir"
done
check_git_repo "$HOME/.password-store"
