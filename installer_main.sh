#!/bin/sh

cd $(dirname $(realpath "$0")) #cd to dotfiles dir
#echo $(realpath .)
sh arch_package_install.sh
sh makesymlinks.sh "$1"
sh custom_bin_scripts.sh
echo "Now run script 'run_root.sh' as root"

