#/bin/zsh
#
# _______| |__  _ __ ___ 
#|_  / __| '_ \| '__/ __|
# / /\__ \ | | | | | (__ 
#/___|___/_| |_|_|  \___|
#                        
# 
#[ $(( ( RANDOM % 2 )  + 1 )) = 1 ] && echo "i <3 hannah" | figlet || echo "hannah is qt" | figlet
# History:
HISTFILE=~/.cache/histfile
HISTSIZE=1000
SAVEHIST=1000

setopt autocd #type name of dir to cd
unsetopt beep #no beep
bindkey -v #vim keys
export KEYTIMEOUT=1 #xtra option for vim keys
zstyle :compinstall filename '/home/maxwell/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall
#
# Enable colors and change prompt:
autoload -U colors && colors
PS1="%B%{$fg[yellow]%}[%{$fg[magenta]%}%n%{$fg[green]%}@%{$fg[blue]%}%M %{$fg[red]%}%~%{$fg[yellow]%}]%{$reset_color%}$%b "

[ -e "$HOME/.config/sh/shrc" ] && source "$HOME/.config/sh/shrc" #load alias and exports
[ -e "$HOME/.zshrc_extra" ] && source "$HOME/.zshrc_extra" #load platform specifcs 

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.


# Use vim keys in tab complete menu:
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -v '^?' backward-delete-char

# Change cursor shape for different vi modes.
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] ||
     [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] ||
       [[ ${KEYMAP} == viins ]] ||
       [[ ${KEYMAP} = '' ]] ||
       [[ $1 = 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select
zle-line-init() {
    zle -K viins # initiate `vi insert` as keymap (can be removed if `bindkey -V` has been set elsewhere)
    echo -ne "\e[5 q"
}
zle -N zle-line-init
echo -ne '\e[5 q' # Use beam shape cursor on startup.
preexec() { echo -ne '\e[5 q' ;} # Use beam shape cursor for each new prompt.


#bindkey -s '^v' 'clear\n' #bind ctrl-v to function
