#!/bin/sh

#userresources=$HOME/.Xresources
#usermodmap=$HOME/.Xmodmap
#sysresources=/etc/X11/xinit/.Xresources
#sysmodmap=/etc/X11/xinit/.Xmodmap

# merge in defaults and keymaps
#if [ -f $sysresources ]; then
#    xrdb -merge $sysresources
#fi

#if [ -f $sysmodmap ]; then
#    xmodmap $sysmodmap
#fi
#if [ -f "$userresources" ]; then
#    xrdb -merge "$userresources"
#fi
#if [ -f "$usermodmap" ]; then
#    xmodmap "$usermodmap"
#fi
# start some nice programs
#if [ -d /etc/X11/xinit/xinitrc.d ] ; then
# for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
#  [ -x "$f" ] && . "$f"
# done
# unset f
#fi

#twm &
#xclock -geometry 50x50-1+1 &
#xterm -geometry 80x50+494+51 &
#xterm -geometry 80x20+494-0 &
#exec xterm -geometry 80x66+0+0 -name login

#the real OG
#exec /usr/bin/i3
if [ $dotfile_tag = "pc" ];
then
    nvidia-settings -a "[gpu:0]/GPUFanControlState=1" -a "[fan:0]/GPUTargetFanSpeed=30"
fi

#if [ $dotfile_tag = "laptop" ]; then
#    xinput set-prop 10 299 1 #enable tapping on touchpad gestures
#    setxkbmap caps:F13
#    touch $HOME/touchfile
#fi

#exec gnome-session
