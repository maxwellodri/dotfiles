#!/bin/sh
xrdb ~/.Xresources &
feh --bg-scale "$dotfiles/images/low-poly_red.jpg" &
dunst &
picom -b --config ~/.config/picom/picom.conf &
/usr/lib/xfce-polkit/xfce-polkit &
[ $dotfiles_tag = "pc" ] && steam -silent &
wal -R &
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
