#!/bin/sh
sleep 1
dunst &
which picom && picom -b --config ~/.config/picom/picom.conf &
polkit-dumb-agent &
systemctl --user import-environment DISPLAY XAUTHORITY #non-xorg vars defined in shrc 
transmission-daemon

$dotfiles/dwm/neovim-server-runner.py --cleanup

$bin/set_kb_map

#/usr/lib/xfce-polkit/xfce-polkit &
$bin/loop_set_kb_map.sh
which slock && xautolock -time 10 -locker slock
$bin/background_set.sh
[ $dotfiles_tag = "pc" ] && steam -silent &

echo "Done startup"
