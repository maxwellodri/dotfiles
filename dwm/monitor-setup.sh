#!/bin/sh
case $dotfiles_tag in 
    pc) 
        #if [ ! -z $(glxinfo -B | grep NVIDIA) ] then;
            xrandr --output DP-2 --primary --mode 2560x1440 --rate 144.00 --output HDMI-0 --mode 1920x1080 --rate 60.00 --right-of DP-2 #amd
            #xrandr --output DisplayPort-2 --primary --mode 2560x1440 --rate 144.00 --output HDMI-A-0 --mode 1920x1080 --rate 60.00 --right-of DisplayPort-2 #amd
            ;;
        *)  
            ;;
esac
