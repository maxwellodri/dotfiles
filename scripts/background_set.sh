#!/bin/sh
[ ! -f "$bin/monitor.sh" ] && feh --no-feh-bg --bg-fill "$dotfiles/images/mountains.jpg" "$dotfiles/images/lofi.jpg"
[ -f "$bin/monitor.sh" ] && $bin/monitor.sh 2,1>~/monitor.sh.log && feh --no-fehbg --bg-fill "$dotfiles/images/mountains.jpg" "$dotfiles/images/lofi.jpg"
