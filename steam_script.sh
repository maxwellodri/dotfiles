#!/bin/bash

#change steams tray icon
olddir="~/.dotfiles_old"
mkdir $olddir #if its not made already
icon="steam_tray_mono.png"
#make a backup:
sudo mv "/usr/share/pixmaps/$icon" "$olddir/$icon"
sudo cp "$dotfiles/steam/$icon" "/usr/share/pixmaps/$icon"


#Now we add scripts for launching games
mkdir -p "$HOME/bin"
echo "Changing directory to scripts folder...\n"
for file in $(find $dotfiles/steam/scripts/*); do
    echo $file
    ln -sf $file $bin/$(basename $file)  #use absolute paths!
done

