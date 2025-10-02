#!/bin/sh
GRACE_PERIOD=900
REPOS="$HOME/source/dotfiles $HOME/source/mykaelium $HOME/source/st $HOME/source/dmenu $HOME/source/dwm ~/.password-store"
dirty_repos=""

for repo in $REPOS; do
    repo_path=$(eval echo "$repo")
    
    [ ! -d "$repo_path/.git" ] && continue
    
    cd "$repo_path" || continue
    
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        newest=$(git ls-files -m -z | xargs -0 stat -c %Y 2>/dev/null | sort -rn | head -n1)
        now=$(date +%s)
        
        if [ -n "$newest" ] && [ $((now - newest)) -gt "$GRACE_PERIOD" ]; then
            dirty_repos="$dirty_repos$(basename "$repo_path")\n"
        fi
    fi
done

if [ -n "$dirty_repos" ]; then
    notify-send -h string:x-canonical-private-synchronous:git_reminder -t 0 \
        "🤓 Git Reminder 📔" "$(printf '%b' "$dirty_repos" | sed '/^$/d')"
fi
