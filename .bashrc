#!/bin/bash
# _               _              
#| |__   __ _ ___| |__  _ __ ___ 
#| '_ \ / _` / __| '_ \| '__/ __|
#| |_) | (_| \__ \ | | | | | (__ 
#|_.__/ \__,_|___/_| |_|_|  \___|
#

PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"' #$USER@HOSTNAME : WORKNG DIR
stty -ixon #Disable ctrl-s and ctrl-q
################
#exports:
###############
export TERM='terminator'
export WEB='firefox'
export EMAIL='maxwellodri@gmail.com'
export EMAILCLIENT='thunderbird'
export EDITOR='vim'
export VISUAL='vim'
export BIN="$HOME/bin"
export bin="$BIN"
export PATH=$PATH:$BIN #add /home/$USER/bin to path
export PATH=$PATH:"$BIN/steam_scripts" #and subfolder for steam scripts
export PATH=$PATH:$HOME/bin
export dl="$HOME/Downloads"


################
#Extras
################
[ -e ~/.bashrc_extra ] && source ~/.bashrc_extra
[ -e ~/.cargo/env ] && source ~/.cargo/env

################
#Aliases:
###############
alias bashrc="vim ~/.bashrc && source ~/.bashrc"
alias bashrctag="vim ~/.bashrc_extra && source ~/.bashrc"
alias bashprofile="vim ~/.bash_profile"
alias xrc="vim ~/.xinitrc"
alias vimrc="vim ~/.vimrc"
alias i3rc="vim $dotfiles/.config/i3/config.base && $dotfiles/makesymlinks.sh $dotfile_tag >> /dev/null && i3-msg reload"
alias bm="vim $dotfiles/scripts/web_bookmarks.txt"
alias mksl="vim $dotfiles/makesymlinks.sh"
alias i3tag="vim $dotfiles/.config/i3/config.extra && $dotfiles/makesymlinks.sh $dotfile_tag >> /dev/null && i3-msg reload"
alias termrc="vim ~/.config/terminator/config"
alias i3sbar="vim ~/.config/i3status/config && i3-msg restart"
alias zathurarc="vim ~/.config/zathura/zathurarc"
alias systemctl="sudo systemctl"
alias ls="ls --color=auto -hN --group-directories-first"
alias l="ls --color=auto -hN --group-directories-first"
alias lsa="ls --color=auto -hNA --group-directories-first"
alias cls="clear && ls"
alias grep="grep --color=auto"
alias dl="cd ~/Downloads"
alias src="cd ~/source"
alias mkdir="mkdir -pv"
alias p="sudo pacman"


################
#Functions
################

#resolves symlinks:
function rlinks(){
    ln -sf "$(realpath "$1")" "$(realpath "$2")"
}
#resolve symlink hell when cd'ing and send self to realpath of present dir
function cdr(){
    cd "$(realpath "$PWD")" || return
}


                                
