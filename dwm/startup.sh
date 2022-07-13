#!/bin/sh
xrdb ~/.Xresources &
dunst &
picom -b --config ~/.config/picom/picom.conf &
/usr/lib/xfce-polkit/xfce-polkit &
[ $dotfiles_tag = "pc" ] && steam -silent &
#feh --bg-scale "$dotfiles/images/low_poly_red.jpg"
wallpaper-show
#notify-send "$dotfiles/images/low-poly_red.jpg"
#wal -R &
#emacs_runner "startup" & 
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
