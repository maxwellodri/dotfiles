#!/bin/sh
xrdb ~/.Xresources &
feh --bg-scale "$dotfiles/images/low-poly_red.jpg" &
dunst &
picom &
/usr/lib/xfce-polkit/xfce-polkit &
wal -R &
echo "Done startup"
#exit
