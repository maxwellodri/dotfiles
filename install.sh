#!/bin/sh

. "$(dirname "$(realpath "$0")")/.config/sh/shutil.sh"

# --other-user <name>: minimal install for a non-primary user (e.g. pi)
#   Runs makesymlinks + custom_bin_scripts only.
#   Skips pacman, system configs, firefox, rust, suckless, fontconfig.
#   If .zshrc_extra.<name> exists in dotfiles, symlinks it over ~/.zshrc_extra.

other_user=""
tag=""
gui_prompt=false
while [ $# -gt 0 ]; do
	case "$1" in
		--other-user)
			other_user="$2"
			shift 2
			;;
		--gui)
			gui_prompt=true
			export SHUTIL_PREFER_GUI=1
			shift
			;;
		*)
			tag="$1"
			shift
			;;
	esac
done

cd "$(dirname "$(realpath "$0")")"

check_kernel

if [ -n "$tag" ]; then
	echo "$tag" > .dotfile_tag
fi

run_elevated_init || exit 1

if [ -n "$other_user" ]; then
	sh helper_scripts/makesymlinks.sh "$tag"
	# Override .zshrc_extra with user-specific variant if it exists
	extra_file="$PWD/.zshrc_extra.$other_user"
	if [ -f "$extra_file" ]; then
		echo "Overriding .zshrc_extra with $extra_file"
		rm -f "$HOME/.zshrc_extra"
		ln -sf "$extra_file" "$HOME/.zshrc_extra"
	fi
	sh helper_scripts/custom_bin_scripts.sh
	exit 0
fi

sh helper_scripts/arch_package_install.sh $1
sh helper_scripts/makesymlinks.sh "$1"
sh helper_scripts/fontconfig.sh
sh helper_scripts/custom_bin_scripts.sh
sh helper_scripts/firefox_user.sh
sh rust/install.sh
bash helper_scripts/install_system_configs.sh #after makesymlinks.sh always need $GIT_ROOT/.dotfile_tag file to be present
bash helper_scripts/download_suckless.sh #Should always be last to provide ssh copying msg, e.g. see script
