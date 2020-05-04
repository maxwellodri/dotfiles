#!/bin/dash
############################
# This script creates symlinks from the home directory to any desired dotfiles in ~/dotfiles, set by the variables below
############################

########### Fixed Variables (dont change) 
dotfiles="$(dirname "$(readlink -f "$0")")" #foldername 
dir=$dotfiles                   # dotfiles directory
olddir=~/.dotfiles_old             # old dotfiles backup directory
i3config=.config/i3/config #combines with below to make i3 
i3statusconfig=.config/i3status/config
zathura=.config/zathura/zathurarc
terminator=.config/terminator/config
sh=.config/sh/shrc

#bspwmconfig=.config/bspwm/bspwmrc
#sxhkdconfig=.config/sxhkd/sxhkdrc

########### Meta Variables
#bsp=" $bspwmconfig $sxhkdconfig" #these arent finished yet in the git repo!
pactl=.config/pulseaudio-ctl/config
i3=" $i3config $i3statusconfig" #i3wm
xfiles=" .xinitrc $zathura"
bash=" .bashrc .bashrc_extra .bash_profile $sh"
zsh=" .zshrc .zshrc_extra .zprofile $sh" 
files=" .vimrc"    
########### Variables
pcfiles=" " #platform specific dotfiles
laptopfiles=" $xfiles $pactl $i3 $zsh $terminator"
thinkpadfiles=" $xfiles $zsh"
chromebookfiles=" "
rpifiles=" "
all="$files$zsh$bash$xfiles$i3$pactl$sh$terminator$zathura" #all files

##########

echo "Beginning script..."
#figure out which system we are on by first variable i.e. $1:

case $1 in
    "chromebook")   tag="$1"
                    files=$chromebookfiles$files
                    ;;

    "laptop")       tag="$1"
                    files=$laptopfiles$files
                    ;;

    "pc")           tag="$1"
                    files=$pcfiles$files
                    ;;

    "thinkpad")     tag="$1"
                    files=$thinkpadfiles$files
                    ;;

    "rpi")          tag="$1"
                    files=$rpifiles$files
                    ;;

    "clean")        echo "Removing all symlinks..." 
                    for file in $all; do
                        [ -L "$HOME/$file" ] && unlink "$HOME/$file" && echo "Unlinked $file"
                    done
                    echo "Finished unlinkng" && exit
                    ;;

    *)              
                    echo "Pick a device and pass as first argument" 
                    exit
                    ;;

esac
# create dotfiles_old in homedir
echo "Creating $olddir for backup of any existing dotfiles in ~"
mkdir -pv $olddir
echo "...done"
echo ""
echo "Making needed parent directories..."
for file in $files; do
    parent="$(dirname "$file")"
    mkdir -p "$HOME/$parent"
    mkdir -p "$olddir/$parent"
done
echo "Done making parent directories."
echo ""

# change to the dotfiles directory
echo "Changing directory to $dir"
cd "$dir" || exit
echo "...Done"
echo ""


# move any existing dotfiles in homedir to dotfiles_old directory, then create symlinks 
for file in $files; do
    echo "Moving any existing $file from ~/ to $olddir"
    mv "$HOME/$file" "$olddir"
    case "$file" in

        "$i3config")            echo "Making backup of old i3-config."
                                mv "$dir/$file" "$olddir/$file.bak"
                                #now cat from source files:
                                echo "#Dont edit this file directly, instead edit the src files and rebuild" > "$dir/$file" #a comment
                                echo " " >> "$dir/$file"
                                #.config/i3/config.base and .config/i3/config/$tag where $tag can be pc/empty/chromebook etc
                                if [ ! -f "$dir/$file.$tag" ]; then 
                                    echo "Custom config for $tag not found, ignoring..."
                                    echo " "
                                    cat "$dir/$file.base" >> "$dir/$file"
                                else
                                    echo "Using $tag as extra"
                                    ln -sf "$dir/$file.$tag" "$dir/$file.extra"
                                    echo "Using cat to create i3config, $dir/$file"
                                    cat "$dir/$file.base" "$dir/$file.$tag" >> "$dir/$file"
                                    echo "from $file.base and $file.$tag"
                                    echo "Done"
                                fi
                                src="$dir/$file"
                                ;;

        ".bashrc_extra")        src="$dir/.bashrc_extra.$tag"
                                ;;

        ".zshrc_extra")         src="$dir/.zshrc_extra.$tag"
                                ;;

        "$i3statusconfig")      src="$dir/$file.$tag"
                                ;;
        
        ".xinitrc")             src="$dir/$file"
                                ;;

        ".bash_profile")        src="$dir/$file.$tag"
                                ;;

        ".zprofile")            src="$dir/$file.$tag"
                                ;;
        "$sh")                  src="$dir/.config/sh/shrc"
                                ;;

        "$zathura")             src="$dir/.config/zathura/zathurarc"
                                ;;

        *)                      src="$dir/$file"
                                ;;
    
    esac 
    echo "Creating symlink from $src to ~/$file."
    echo " "
    ln -s "$src" "$HOME/$file"
done

echo "Done."
echo "tag variable used = $tag"
echo "Script is finished."

