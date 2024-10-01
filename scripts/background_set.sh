#!/bin/sh
[ ! -f "$bin/monitor.sh" ] && feh --no-feh-bg --bg-fill "$dotfiles/images/mountains.jpg" "$dotfiles/images/lofi.jpg"
[ -f "$bin/monitor.sh" ] && $bin/monitor.sh && feh --no-fehbg --bg-fill "$dotfiles/images/mountains.jpg" "$dotfiles/images/lofi.jpg"
