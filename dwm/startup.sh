#!/bin/sh
dunst &
picom -b --config ~/.config/picom/picom.conf &
polkit-dumb-agent &
systemctl --user import-environment DISPLAY XAUTHORITY #non-xorg vars defined in shrc 
transmission-daemon

$dotfiles/dwm/neovim-server-runner.py --cleanup

$bin/set_kb_map

#/usr/lib/xfce-polkit/xfce-polkit &
[ $dotfiles_tag = "pc" ] && steam -silent &
[ -f "$bin/monitor.sh" ] && $bin/monitor.sh
sleep 0.5
feh --bg-scale "$dotfiles/images/treesketch.jpg"
$bin/loop_set_kb_map.sh
#wallpaper-show
#notify-send "$dotfiles/images/low-poly_red.jpg"
#wal -R &
#emacs_runner "startup" & 
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
