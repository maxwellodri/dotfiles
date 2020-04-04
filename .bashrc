################
#exports:
###############
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin #set some nice paths
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
export PATH=$PATH:/snap/bin
export PATH=$PATH:$bin/etc
export PATH=$PATH:$HOME/bin
export Downloads="$(realpath $HOME/Downloads)" #may want to symlink this
export src="$HOME/src"
export bookmarks="$dotfile/bin/web_bookmarks.txt"
export dl="$Downloads"

################
#Aliases:
###############
alias bashrc="vim ~/.bashrc && source ~/.bashrc"
alias xrc="vim ~/.xinitrc"
alias vimrc="vim ~/.vimrc"
alias i3rc="vim $dotfiles/.config/i3/config.base && $dotfiles/makesymlinks.sh $dotfile_tag >> /dev/null && i3-msg reload"
alias bashrctag="vim ~/.bashrc_extra && source ~/.bashrc"
alias bashprofile="vim ~/.bash_profile"
alias i3tag="vim $dotfiles/.config/i3/config.extra && $dotfiles/makesymlinks.sh $dotfile_tag >> /dev/null && i3-msg reload"
alias cati3="cat ~/.config/i3/config"
alias termrc="vim ~/.config/terminator/config"
alias i3sbar="vim ~/.config/i3status/config && i3-msg restart"
alias systemctl="sudo systemctl"
alias ls="ls --color=auto -hN --group-directories-first"
alias l="ls --color=auto -hN --group-directories-first"
alias lsa="ls --color=auto -hNA --group-directories-first"
alias clc="clear"
alias cls="clear && ls"
alias clsa="clear && ls -A"
alias grep="grep --color=auto"
alias dl="cd ~/Downloads"
alias bookmarks="vim $dotfiles/bin/web_bookmarks.txt"
alias todo='vim ~/todo'

################
#Extras
################
if [ -e ~/.bashrc_extra ]; #check if file exists first, allows for symlinks
then
    source ~/.bashrc_extra
fi
if [ -e ~/.cargo/env ];
then
    source ~/.cargo/env
fi
PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"' #$USER@HOSTNAME : WORKNG DIR
stty -ixon #Disable ctrl-s and ctrl-q

################
#Functions
################

#resolves symlinks:
function rlinks(){
    ln -sf $(realpath $1) $(realpath $2)
}
#resolve symlink hell when cd'ing and send self to realpath of present dir
function cdr(){
    cd "$(realpath $PWD)"
}



