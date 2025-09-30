#!/bin/sh

GRACE_PERIOD=900  # 15 minutes in seconds
REPOS="dotfiles mykaelium st dmenu dwm"

for repo in $REPOS; do
    repo_path="$HOME/source/$repo"
    
    [ ! -d "$repo_path/.git" ] && continue
    
    cd "$repo_path" || continue
    
    # Check if repo is dirty
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        # Get timestamp of newest modified tracked file
        newest=$(git ls-files -m -z | xargs -0 stat -c %Y 2>/dev/null | sort -rn | head -n1)
        now=$(date +%s)
        
        # Only notify if newest change is older than grace period
        if [ -n "$newest" ] && [ $((now - newest)) -gt "$GRACE_PERIOD" ]; then
            notify-send "Git Reminder" "Uncommitted changes in $repo"
        fi
    fi
done
