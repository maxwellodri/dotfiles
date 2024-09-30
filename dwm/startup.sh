#!/bin/sh
dunst &
which picom && picom -b --config ~/.config/picom/picom.conf &
polkit-dumb-agent &
systemctl --user import-environment DISPLAY XAUTHORITY #non-xorg vars defined in shrc 
transmission-daemon

$dotfiles/dwm/neovim-server-runner.py --cleanup

$bin/set_kb_map
#$bin/loop_set_kb_map.sh

which slock && xautolock -time 10 -locker slock
[ $dotfiles_tag = "pc" ] && steam &
[ $dotfiles_tag = "pc" ] && signal-desktop &
[ $dotfiles_tag = "pc" ] && spotify-launcher &
[ $dotfiles_tag = "pc" ] && thunderbird &
[ $dotfiles_tag = "pc" ] && pgrep -x mpd || mpd
background_set.sh

echo "Done startup"
