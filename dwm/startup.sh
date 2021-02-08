#!/bin/sh
feh --bg-scale "$dotfiles/images/low-poly_mtn.jpg" &
dunst &
picom &
/usr/lib/xfce-polkit/xfce-polkit &
wal -R &
echo "Done startup"
#exit
