#!/bin/sh
if [ -n "$1" ]; then
    tty_n="$1"
else
    tty_n="1"
fi

echo "tty_n = $tty_n"
echo "$DISPLAY"
echo "$XDG_VTNR"
if  [ ! "$DISPLAY" ] && [ "$XDG_VTNR" -eq "$tty_n" ]; then
    echo "passing"
fi

