#!/bin/sh
/usr/lib/xfce-polkit/xfce-polkit &
feh --bg-scale "$dotfiles/images/arch-dingo.jpg" &
dunst &
picom &
exit
