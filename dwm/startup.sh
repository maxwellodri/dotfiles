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
[ ! -f "$bin/monitor.sh" ] && feh --bg-fill "$dotfiles/images/mountains.jpg" "$dotfiles/images/lake.jpg"
[ -f "$bin/monitor.sh" ] && $bin/monitor.sh && feh --bg-fill "$dotfiles/images/mountains.jpg" "$dotfiles/images/lake.jpg"
[ $dotfiles_tag = "pc" ] && steam -silent &
#wallpaper-show
#notify-send "$dotfiles/images/low-poly_red.jpg"
#wal -R &
#emacs_runner "startup" & 
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
