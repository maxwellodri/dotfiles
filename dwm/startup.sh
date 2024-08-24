#!/bin/sh
dunst &
picom -b --config ~/.config/picom/picom.conf &
polkit-dumb-agent &
systemctl --user import-environment DISPLAY XAUTHORITY #non-xorg vars defined in shrc 
transmission-daemon

server_path="$HOME/.cache/nvim/godot-server.pipe"
[ -f "$server_path" ] && rm server_path
nohup $dotfiles/dwm/godot-neovim-runner.py --daemon & disown

$bin/set_kb_map

#/usr/lib/xfce-polkit/xfce-polkit &
[ $dotfiles_tag = "pc" ] && steam -silent &
[ -f "$bin/monitor.sh" ] && $bin/monitor.sh
feh --bg-scale "$dotfiles/images/treesketch.jpg"
$bin/loop_set_kb_map.sh
#wallpaper-show
#notify-send "$dotfiles/images/low-poly_red.jpg"
#wal -R &
#emacs_runner "startup" & 
#$dotfiles/monitor-setup.sh &
echo "Done startup"
#exit
