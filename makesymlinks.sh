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
terminatorconfig=.config/terminator/config

#bspwmconfig=.config/bspwm/bspwmrc
#sxhkdconfig=.config/sxhkd/sxhkdrc

########### Meta Variables
#bsp=" $bspwmconfig $sxhkdconfig" #these arent finished yet in the git repo!
pactl=.config/pulseaudio-ctl/config
i3=" $i3config $i3statusconfig" #i3wm
xfiles=" .xinitrc $terminatorconfig $zathura"
xfiles=" .xinitrc"
terminatorconfig=.config/terminator/config
bash=" .bashrc .bashrc_extra .bash_profile"
files=" .vimrc"    
########### Variables
pcfiles=" " #platform specific dotfiles
laptopfiles=" $xfiles $pactl $i3 $bash $terminatorconfig"
thinkpadfiles=" $xfiles $bash"
chromebookfiles=" "
rpifiles=" "

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

    *)              if [ -n "$dotfiles_tag" ]; then
                        #if dotfiles_tag is defined, in bashrc_extra or similar, then dont need to explicitly pass $1, and can infer from this
                        tag="$dotfiles_tag"                      
                    else
                        echo "Pick a device and pass as first argument" 
                        echo "Exiting..."
                        exit
                    fi
                    ;;

esac
# create dotfiles_old in homedir
echo "Creating $olddir for backup of any existing dotfiles in ~"
mkdir -p $olddir
echo "...done"


echo ""
echo "Making needed parent directories, ignore any warnings about existing folders..."
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
                                    ln -sf "$dir/$file.$tag" "$dir/$file.extra"
                                    cat "$dir/$file.base" "$dir/$file.$tag" >> "$dir/$file"
                                fi
                                src="$dir/$file"
                                ;;

        ".bashrc_extra")         src="$dir/.bashrc_extra_$tag"
                                ;;

        "$i3statusconfig")       src="$dir/$file.$tag"
                                ;;
        
        ".xinitrc")             src="$dir/$file.$tag"
                                ;;

        ".bash_profile")        src="$dir/$file.$tag"
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

