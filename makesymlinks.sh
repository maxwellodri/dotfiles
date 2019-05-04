#!/bin/bash
############################
# This script creates symlinks from the home directory to any desired dotfiles in ~/dotfiles, set by the variable 'files' below
############################

########## Variables
i3config=.config/i3/config #less annoying than writing fullpath
i3statusconfig=.config/i3status/config
terminatorconfig=.config/terminator/config
dir=~/dotfiles                    # dotfiles directory
olddir=~/.dotfiles_old             # old dotfiles backup directory
files=".bashrc .vimrc .bashrc_extra .bashrc_cdr $i3config $i3statusconfig $terminatorconfig"    # list of files/folders to symlink in homedir
pcfiles=" .xinitrc .bash_profile" #platform specific dotfiles
chromebookfiles=" "
##########

echo -e "Beginning script...\n"
#figure out which system we are on by first variable i.e. $1:
if [ "$1" == "chromebook" ]
then
    tag="chromebook"
    files=$files$chromebookfiles
elif [ "$1" == "pc" ]
then
    tag="pc"
    files=$files$chromebookfiles
elif [ "$!" == "empty" ]
then 
    tag="empty"
elif [ -z $1 ]
then
    if [ -n $1 ]
    then
        tag=$dotfile_tag
        if [ $tag == "pc" ];
        then
            files="$files$pcfiles"
        elif [ $tag == "chromebook" ];
        then
            files="$files$pcfiles"
        fi
    fi
else
    tag="empty"
    echo -e "Use first argument as either chromebook or pc for specific extra dotfiles, otherwise adding empty dotfile" 
fi
echo -e "Using $tag setup\n"





# create dotfiles_old in homedir
echo "Creating $olddir for backup of any existing dotfiles in ~"
mkdir -p $olddir
echo "...done"


echo -e "\nMaking needed parent directories, ignore any warnings about existing folders..."
for file in $files; do
    parent=$(dirname $file)
    mkdir -p ~/$parent
    mkdir -p $olddir/$parent
done
echo -e "Done making parent directories.\n"

# change to the dotfiles directory
echo "Changing to the $dir directory"
cd $dir
echo -e "...Done\n"


# move any existing dotfiles in homedir to dotfiles_old directory, then create symlinks 
for file in $files; do
    if [ $file == "$i3config" ]
    then
        #for i3-config we build it from source files, since i3 doesnt allow for multiple config files:
        #first make backup:
	echo "Making backup of old i3-config."
        mv $dir/$file $olddir/$file.bak
        #now build from source files:
        echo "#Dont edit this file directly, instead edit the src files and rebuild" > $dir/$file
        echo -e "\n" >> $dir/$file
        #.config/i3/config.base and .config/i3/config/$tag where $tag can be pc/empty/chromebook etc
        if [ ! -f "$dir/$file.$tag" ]
        then 
            echo -e "Custom config for $tag not found, using empty one...\n"
            cat $dir/$file.base $dir/$file.empty >> $dir/$file
            ln -sf $dir/$file.empty $dir/$file.extra
        else
            cat $dir/$file.base $dir/$file.$tag >> $dir/$file
            ln -sf $dir/$file.$tag $dir/$file.extra
        fi
    fi
    echo "Moving any existing $file from ~ to $olddir"
    mv ~/$file $olddir
    if [ ".bashrc_extra" == $file ]
    then
        src="$dir/.bashrc_extra_$tag"
    elif [ "$i3statusconfig" == $file ]
    then
        src="$dir/$file.$tag"
    else
        src=$dir/$file
    fi
    echo  -e "Creating symlink from $src to ~/$file.\n"
    ln -s $src ~/$file
    echo $file
done
echo -e "\nRun source ~/.bashrc for convenience..."
source ~/.bashrc
echo -e "Done.\n"
echo -e "tag variable used = $tag"
echo -e "\nScript is finished.\n"



