#!/bin/sh
feh --bg-scale "$dotfiles/images/arch-dingo.jpg" &
dunst &
/usr/lib/xfce-polkit/xfce-polkit 2>/dev/null &
picom &
exit
