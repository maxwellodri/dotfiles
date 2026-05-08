#!/bin/bash
REPO_ROOT="$(git -C "$(dirname "$(realpath "$0")")" rev-parse --show-toplevel)"
. "$REPO_ROOT/.config/sh/shutil.sh"

if [ "$bin" != "$HOME/bin" ] || [ -z "$dotfiles" ]; then
    echo "bin var != ~/bin or dotfiles var doesnt exist"
    exit
fi
dscripts="$dotfiles/scripts"
case "$1" in
    "clean")
                for file in "$bin"/*; do
                    if [ -L "$file" ]; then
                        echo "Unlinking $(basename "$file") in bin"
                        unlink "$file"
                    fi
                done
                echo ""
                ;;

        *)
                mkdir -p "$HOME/.cache/dotfiles"
                echo "bin path: $bin"
                symlink_contents "$dscripts" "$bin" --exclude "__pycache__"
                prune_dead_symlinks "$bin" --source "$dscripts"
                echo ""
                ;;
esac
