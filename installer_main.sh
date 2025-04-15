#!/bin/sh

cd $(dirname $(realpath "$0")) #cd to dotfiles dir
sh helper_scripts/arch_package_install.sh $1
sh helper_scripts/makesymlinks.sh "$1"
sh helper_scripts/custom_bin_scripts.sh
sh helper_scripts/firefox_user.sh
bash helper_scripts/download_suckless.sh #Should always be last to provide ssh copying msg, e.g. see script
echo "Now run script 'run_root.sh' as root"
