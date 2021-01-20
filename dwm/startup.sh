#!/bin/sh
feh --bg-scale "$dotfiles/images/arch-dingo.jpg" &
dunst &
picom &
/usr/lib/xfce-polkit/xfce-polkit &
echo "Done startup"
#exit
