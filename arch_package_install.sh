#!/bin/sh
#to install: cat $FILE | grep -v # | xargs sudo pacman -S --noconfirm -needed
cat archlinux_x86_64_packages | grep -v "#" | xargs sudo pacman -S --noconfirm --needed
