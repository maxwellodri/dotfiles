#!/bin/sh
#setsid dunst & # Using service file to make it resistant to OOM killer
which picom && picom -b --config ~/.config/picom/picom.conf &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
systemctl --user import-environment DISPLAY XAUTHORITY #non-xorg vars defined in shrc 
setsid alacritty --daemon --socket "$XDG_RUNTIME_DIR/alacritty.sock" &
#pgrep -xf "transmission-daemon --no-auth" || ( echo "Starting transmission-daemon" && transmission-daemon --no-auth )


[ -n "$dotfiles" ] && "$dotfiles/dwm/neovim-server-runner.py" --cleanup

#( which slock && xautolock -time 10 -locker slock) &
[ "${dotfiles_tag:-}" = "pc" ] && "${bin:-}/steam" &
[ "${dotfiles_tag:-}" = "pc" ] && signal-desktop &
[ "${dotfiles_tag:-}" = "pc" ] && spotify-launcher &
[ "${dotfiles_tag:-}" = "pc" ] && thunderbird &
[ "${dotfiles_tag:-}" = "pc" ] && (pgrep -x mpd || mpd)
[ "${dotfiles_tag:-}" = "pc" ] && nicotine &
[ -f "$bin/monitor.sh" ] && "$bin/monitor.sh"
background_set.sh &
"$bin/set_kb_map" &
rm -f ~/.cache/tsp_ytdlp/*
tmux kill-session -t tsp_ytdlp
#tmux new-session -d -s tsp_ytdlp 'tsp_ytdlp --daemon'

echo "Done startup"
