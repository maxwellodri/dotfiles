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


echo $WM

#export DESKTOP_SESSION=plasma
#exec startplasma-x11 

export LUTRIS_SKIP_INIT
[ "$(basename "$WM")" = "dwm" ] && [ -f "$dotfiles/dwm/dwmshell" ] && "$dotfiles/dwm/dwmshell"  #shell script to start for dwm, for starting other programs
if [ "$(basename "$WM")" = "dwm" ]; then
        sxhkd &
        # make CapsLock behave like Ctrl:
        #setxkbmap -option caps:escape
        [[ -f ~/.Xmodmap ]] && xmodmap ~/.Xmodmap
    while [ "$KILLDWM" != "true" ]; do
	    ssh-agent dwm
    done
    unset KILLDWM
elif [ "$(basename "$WM")" = "penrose" ]; then
    $dotfiles/penrose/startup.sh
    #xautolock -time 20 -locker "lockme" -detectsleep &
    ssh-agent penrose
fi
