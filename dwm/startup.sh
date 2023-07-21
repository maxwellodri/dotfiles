#!/bin/sh
server_path="$HOME/.cache/nvim/godot-server.pipe"
[ -f "$server_path" ] && rm server_path
dunst &
#picom -b --config ~/.config/picom/picom.conf &
polkit-dumb-agent &
#/usr/lib/xfce-polkit/xfce-polkit &
[ $dotfiles_tag = "pc" ] && steam -silent &
$bin/monitor.sh && feh --bg-scale "$dotfiles/images/treesketch.jpg"
#wallpaper-show
#notify-send "$dotfiles/images/low-poly_red.jpg"
#wal -R &
#emacs_runner "startup" & 
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
