#!/bin/sh
#to install: cat $FILE | grep -v # | xargs sudo pacman -S --noconfirm -needed
grep -o '^[^#]*' archlinux_x86_64_packages | xargs sudo pacman -S --noconfirm --needed
