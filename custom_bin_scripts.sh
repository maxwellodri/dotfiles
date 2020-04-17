#!/bin/sh
#adds wrappers and the like to path
#assumes $bin is in path -> i.e. need makesymlink script to have already been run
if [ "$bin" != "$HOME/bin" ] || [ -z "$dotfiles" ]; then
    exit
fi

case "$1" in
    "clean")
                for file in "$bin"/*; do
                    if [ -f "$file" ]; then
                        unlink "$file"
                    fi
                    if [ -d "$file" ]; then
                        unlink "$file"
                    fi
                done
                ;;

        *)  
                mkdir -p "$bin"
                cd "$dotfiles/bin" || exit
                for file in $(realpath "$(find .)"); do
                    if [ "$file" != "$dotfiles/bin" ]; then
                        ln -sf "$file" "$bin"
                        echo "Added to bin: $file"
                    fi
                done
                ;;
esac


