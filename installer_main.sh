#!/bin/sh

cd $(dirname $(realpath "$0")) #cd to dotfiles dir
#echo $(realpath .)
sh helper_scripts/arch_package_install.sh
sh helper_scripts/makesymlinks.sh "$1"
sh helper_scripts/custom_bin_scripts.sh
sh helper_scripts/firefox_user_prefs.sh
echo "Now run script 'run_root.sh' as root"

