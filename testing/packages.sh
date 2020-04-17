#!/bin/dash
__distro="$(cat /etc/*-release | grep PRETTY_NAME= | cut -c "$(echo PRETTY_NAME= | wc -m)"- | tr -d '"')" #gets distro name
__architecture="$(lscpu | grep Architecture | cut -c 34-)" #gets cpu architecture

case $__architecture in
    "x86_64")
                        case $__distro in
                            "Arch Linux")   
                                                echo "Using $__distro"
                                                ;;
                            *) 
                                                echo "Unkown Distro, using $__distro..."
                                                ;;

                        esac
    ;;

    *)                 
                        echo "Can't get CPU Architecture, see output of lscpu | grep Architecture ..."
                        lscpu | grep Architecture
                        ;;
esac
#pacmixer for ncurses UX, pa-ctl for direct input ctl
#pulseaudio-ctl
#pacmixer
#ctags is pacman package but for tagbar vim plugin:
#ctags
#https://github.com/enkore/i3pystatus/ #alternate to py3status
#digimend-kernel-drivers-dkms-git #for HUION 610PRO Drawing Tablet

