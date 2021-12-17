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
echo $WM

#export DESKTOP_SESSION=plasma
#exec startplasma-x11 

[ "$(basename "$WM")" = "dwm" ] && [ -f "$dotfiles/dwm/dwmshell" ] && "$dotfiles/dwm/dwmshell"  #shell script to start for dwm, for starting other programs
if [ "$(basename "$WM")" = "dwm" ]; then
        sxhkd &
        xrandr --output HDMI-1 --primay --mode 1920x1080 --rate 60.00
        # make CapsLock behave like Ctrl:
        setxkbmap -option caps:escape
        # make short-pressed Ctrl behave like Escape:
        #xcape -e 'Control_L=Escape'
        #xautolock -time 20 -locker "lockme" -detectsleep &
    while [ "$KILLDWM" != "true" ]; do
	    ssh-agent dwm
    done
    unset KILLDWM
elif [ "$(basename "$WM")" = "penrose" ]; then
    $dotfiles/penrose/startup.sh
    #xautolock -time 20 -locker "lockme" -detectsleep &
    ssh-agent penrose
fi
