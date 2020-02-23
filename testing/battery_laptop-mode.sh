#!/bin/bash
#make changes to config files then restart systemd unit:
#e.g. 
#sudo systemctl restart laptop-mode
files="conf.d/ laptop-mode.conf"
src="$dotfiles/laptop-mode"
dest="/etc/laptop-mode"
olddir="$HOME/.dotfiles_old$dest"
#require root privileges:
mkdir -p $olddir
sudo mkdir -p $dest

for file in $files; do
    if [ -e "$dest/$file" ];
    then
        cp $dest/$file $olddir/$file -r
    fi
    sudo ln -sf $src/$file $dest/$file
done
