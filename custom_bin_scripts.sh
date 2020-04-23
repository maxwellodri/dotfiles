#!/bin/bash
#adds wrappers and the like to path
#assumes $bin is in path -> i.e. need makesymlink script to have already been run
if [ "$bin" != "$HOME/bin" ] || [ -z "$dotfiles" ]; then
    exit
fi
dscripts="$dotfiles/scripts"
case "$1" in
    "clean")
                for file in "$bin"/*; do
                    if [ -L "$file" ]; then #symbolic link
                        echo "Unlinking $(basename "$file") in bin"
                        unlink "$file"
                    fi
                done
                echo "Done"
                ;;

        *)  
                mkdir -p "$bin"
                cd "$dscripts" || exit
                echo "bin path: $bin"
                find "$PWD" ! -name "$(printf "*\n*")" > tmpfile
                while IFS= read -r file
                do
                    if [ "$file" != "$dscripts" ]; then
                            ln -sf "$file" "$bin"
                            echo "Adding to bin: $(basename "$file")"
                    fi
                done < tmpfile
                rm tmpfile
                echo "Done"
                ;;
esac


