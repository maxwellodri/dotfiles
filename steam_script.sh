#!/bin/sh

icon="steam_tray_mono.png"
olddir="~/.dotfiles_old"

if [ -z "$1" ]; #if run with no arguments then install scripts
then
    #change steams tray icon
    mkdir $olddir #if its not made already
    #make a backup:
#    sudo mv "/usr/share/pixmaps/$icon" "$olddir/$icon"
#    sudo cp "$dotfiles/steam/$icon" "/usr/share/pixmaps/$icon"
    #Now we add scripts for launching games
    mkdir -p "$HOME/bin"
    echo "Changing directory to scripts folder...\n"
    for file in $(find $dotfiles/steam/scripts/*); do
        echo "Linking $(basename $file)..."
        ln -sf $file $bin/$(basename $file)  #use absolute paths!
    done
elif [ "$1" = "remove" ]; #removal - works for any number of installed sccripts - incl manually linked ones
then
    #ignore icon, can do that manually, care more about keeping bin folder clean
    for file in $(find $dotfiles/steam/scripts/*); do
        #echo $file
        if [ -L $bin/$(basename $file) ]; #if symbolic link
        then
            unlink $bin/$(basename $file)
            echo "unlinked $bin/$(basename $file)"
        fi
    done
elif [ "$1" = "restoreicon" ]; #restore icon - requires installation to have been run or wont work
then
    sudo mv "$olddir/$icon" "/usr/share/pixmaps/$icon"
else
    echo "Invalid Arg"
fi

