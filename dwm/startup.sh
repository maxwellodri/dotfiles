#!/bin/sh
xrdb ~/.Xresources &
feh --bg-scale "$dotfiles/images/low-poly_red.jpg" &
dunst &
picom &
/usr/lib/xfce-polkit/xfce-polkit &
[ $dotfiles_tag = "pc" ] && steam -silent &
wal -R &
emacs_runner "startup" & 
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
