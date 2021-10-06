#!/bin/sh
xrdb ~/.Xresources &
feh --bg-scale "$dotfiles/images/low-poly_red.jpg" &
dunst &
picom &
/usr/lib/xfce-polkit/xfce-polkit &
steam -silent &
wal -R &
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
