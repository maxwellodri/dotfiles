#!/bin/sh
userresources=$HOME/.Xresources
usermodmap=$HOME/.Xmodmap
sysresources=/etc/X11/xinit/.Xresources
sysmodmap=/etc/X11/xinit/.Xmodmap

# merge in defaults and keymaps

if [ -f $sysresources ]; then
    xrdb -merge $sysresources
fi

if [ -f $sysmodmap ]; then
    xmodmap $sysmodmap
fi

if [ -f "$userresources" ]; then
    xrdb -merge "$userresources"
fi

if [ -f "$usermodmap" ]; then
    xmodmap "$usermodmap"
fi

if [ -d /etc/X11/xinit/xinitrc.d ] ; then
 for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
  [ -x "$f" ] && . "$f"
 done
 unset f
fi

#twm &
#xclock -geometry 50x50-1+1 &
#xterm -geometry 80x50+494+51 &
#xterm -geometry 80x20+494-0 &
#exec xterm -geometry 80x66+0+0 -name login

setxkbmap -option caps:escape 
#change capslock to a 2nd escape
[ "$(basename "$WM")" = "dwm" ] && [ -f "$dotfiles/dwm/dwmshell" ] && "$dotfiles/dwm/dwmshell"  #shell script to start for dwm, for starting other programs
if [ "$(basename "$WM")" = "dwm" ]; then
    while [ "$KILLDWM" != "true" ]; do
        setxkbmap -option caps:escape 
        sxhkd &
	    ssh-agent dwm
    done
    unset KILLDWM
elif ["$(basename "$WM")" = "bspwm" ]; then
    sxhkd &
    exec bspwm
else 
    exec "$WM"
fi
