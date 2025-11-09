#!/bin/sh

cd $(dirname $(realpath "$0")) #cd to dotfiles dir
sh helper_scripts/arch_package_install.sh $1
sh helper_scripts/makesymlinks.sh "$1"
sh helper_scripts/custom_bin_scripts.sh
sh helper_scripts/firefox_user.sh
sh rust/install.sh
bash helper_scripts/install_system_configs.sh #after makesymlinks.sh always need $GIT_ROOT/.dotfile_tag file to be present
bash helper_scripts/download_suckless.sh #Should always be last to provide ssh copying msg, e.g. see script
