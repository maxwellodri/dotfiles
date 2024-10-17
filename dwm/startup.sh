#!/bin/sh
dunst &
which picom && picom -b --config ~/.config/picom/picom.conf &
polkit-dumb-agent &
systemctl --user import-environment DISPLAY XAUTHORITY #non-xorg vars defined in shrc 
pgrep -xf "transmission-daemon --no-auth" || ( echo "Starting transmission-daemon" && transmission-daemon --no-auth )


$dotfiles/dwm/neovim-server-runner.py --cleanup

( which slock && xautolock -time 10 -locker slock) &
[ $dotfiles_tag = "pc" ] && steam &
[ $dotfiles_tag = "pc" ] && signal-desktop &
[ $dotfiles_tag = "pc" ] && spotify-launcher &
[ $dotfiles_tag = "pc" ] && thunderbird &
[ $dotfiles_tag = "pc" ] && pgrep -x mpd || mpd
[ $dotfiles_tag = "pc" ] && nicotine &
background_set.sh &
$bin/set_kb_map &

echo "Done startup"
