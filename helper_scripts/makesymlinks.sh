#!/bin/sh
############################
# This script creates symlinks from the home directory to any desired dotfiles in ~/dotfiles, set by the variables below
############################

########### Fixed Variables (dont change)
dir="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)" #dotfiles git root directory
i3config=.config/i3/config #combines with below to make i3
i3statusconfig=.config/i3status/config
dotfiles=.config/dotfiles/
qz=.config/qz/
zathura=.config/zathura/zathurarc
terminator=.config/terminator/config
sh=.config/sh/
pam=.pam_environment
picom=.config/picom/picom.conf
dunst=.config/dunst/dunstrc
pactl=.config/pulseaudio-ctl/config
newsboat=.config/newsboat/config
ytdl=.config/youtube-dl/config
tmux=".config/tmux/"
gpg=.gnupg/gpg-agent.conf
emacs=".emacs.d/init.el"
mpd=" .config/mpd/mpd.conf"
nix=" .config/nix/nix.conf"
vimpc=" .config/vimpc/vimpcrc"
bsp=".config/bspwm/bspwmrc .config/bspwm/terminals .config/bspwm/swallow .config/bspwm/noswallow"
sxhkdconfig=.config/sxhkd/sxhkdrc
rofi=.config/rofi/config.rasi
gitconfig=.config/git/
eww=.config/eww/
mpv=.config/mpv/
gtk=".config/gtk-2.0 .config/gtk-3.0 .config/gtk-4.0 .config/gtkrc .config/gtkrc-2.0"
qt=".config/Trolltech.conf .config/qt6ct/qt6ct.conf"
npm=".config/npm/"
faucet=".config/faucet/"
alacritty=".config/alacritty/"
wezterm=".config/wezterm/"
opencode=".config/opencode/opencode.json .config/opencode/skill/ .config/opencode/AGENTS.md .config/opencode/agents .config/opencode/plugins"


########### Meta Variables
i3=" $i3config $i3statusconfig"
xfiles=" .config/X11/xinitrc .config/X11/.Xresources .config/X11/.Xmodmap .config/neovide $zathura $picom $dunst $ncmpcpp $sxhkdconfig $rofi $gtk $qt $alacritty $wezterm"
bash=" .bashrc .bashrc_extra .bash_profile $sh $pam"
zsh=" .zshrc .zshrc_extra .zprofile .config/zsh $sh $pam"
files=" .config/vim/ .config/nvim/ $ytdl $newsboat $tmux $gpg $gitconfig $npm $faucet"

###########
pcfiles=" $xfiles $zsh $mpv $mpd $vimpc $nix $dotfiles $qz $eww $opencode" #platform specific dotfiles
hackermanfiles=" $xfiles $zsh $mpv $nix $dotfiles $qz $eww $opencode"

##########

#figure out which system we are on by first variable i.e. $1:

log() { [ -n "${VERBOSE:-}" ] && echo "$@"; }

case $1 in
    "pc")           tag="$1"
        files=$pcfiles$files
        mkdir -p ~/.local/share/dwm/
        mkdir -p "$XDG_CACHE_HOME/dotfiles/{whisper_models,whisper_audio,llama_models}"
        ln -sf "$PWD/dwm/startup.sh" "$HOME/.local/share/dwm/autostart.sh"
        ;;
    "hackerman")    tag="$1"
        files=$hackermanfiles$files
        mkdir -p ~/.local/share/dwm/
        ln -sf "$PWD/dwm/startup.sh" "$HOME/.local/share/dwm/autostart.sh"
        ;;

    "clean")        echo "Removing all symlinks..."
        for file in $all; do
            [ -L "$HOME/$file" ] && unlink "$HOME/$file" && echo "Unlinked $file"
        done
        echo "Finished unlinkng"
        exit
        ;;

    *)
        echo "Pick a device and pass as first argument"
        exit
        ;;

    esac

    echo "$tag" > "$PWD/.dotfile_tag"

# Iterate through files and remove trailing slash if it's a directory
for file in $files; do
    if [ -d "$file" ] && [[ "$file" == */ ]]; then
        # Remove trailing slash
        file="${file%/}"
    fi
    # Rebuild files string
    new_files="$new_files $file"
done
# Redefine files without trailing slashes
files="$new_files"

# create dotfiles_old in homedir
olddir=$(mktemp -d)
log "Creating $olddir for backup of any existing dotfiles in ~"
log "Making needed parent directories..."
for file in $files; do
    parent="$(dirname "$file")"
    mkdir -p "$HOME/$parent"
    mkdir -p "$olddir/$parent"
done
log "Done making parent directories."

cd "$dir" || exit
log "Changed directory to $dir"

for file in $files; do
    dest="$HOME/$file"
    [ -e "$dest" ] && echo "Moving existing $file from $dest to $olddir" && mv "$dest" "$olddir"
    case "$file" in
        ".bashrc_extra")        src="$dir/.bashrc_extra.$tag"
            ;;

        ".zshrc_extra")         src="$dir/.zshrc_extra.$tag"
            ;;
        ".zprofile")            src="$dir/$file.$tag"
            ;;
        "$i3statusconfig")      src="$dir/$file.$tag"
            ;;

        "$sh")                  src="$dir/.config/sh/shrc"
            ;;

        "$zathura")             src="$dir/.config/zathura/zathurarc"
            ;;

        .vimrc)                 src="$dir/$file"
            ln -s "$src" "$HOME/.config/nvim/vimrc"
            ;;
        *)                      src="$dir/$file"
            ;;

        esac
        ln -s "$src" "$HOME/$file"
    done

