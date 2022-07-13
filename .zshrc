#!/bin/zsh
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

#(cat ~/.cache/wal/sequences &) #pywal
[ -e ~/.cache/wal/colors-tty.sh ] && source ~/.cache/wal/colors-tty.sh
[ -e /etc/profile.d/google-cloud-sdk.sh ] && source /etc/profile.d/google-cloud-sdk.sh
setopt autocd #type name of dir to cd
unsetopt beep #no beep
bindkey -v #vim keys
#set yanking to yank to system clipboard
function vi-yank-xclip {
    zle vi-yank
   echo "$CUTBUFFER" | xclip -i #xclip is obviously X11/Linux only
}
zle -N vi-yank-xclip
bindkey -M vicmd 'y' vi-yank-xclip

source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

function _fuzzy_vim {
    #zle push-input
    zle clear-input
    BUFFER="source $bin/fuzzy_vim"
    zle accept-line
    #zle clear-input
    #BUFFER="clear"
    #zle accept-line

}

function _sterm {
    #zle push-input
    zle clear-input
    BUFFER=" setsid -f st -d . 1&>/dev/null" #space before setsid so it doesnt show up in history

    zle accept-line
    #zle clear-input
    #BUFFER="clear"
    #zle accept-line

}

zle -N _fuzzy_vim
bindkey -M vicmd '^X' _fuzzy_vim
bindkey -M viins '^X' _fuzzy_vim

zle -N _sterm
bindkey -M vicmd '^T' _sterm
bindkey -M viins '^T' _sterm #overrides default fzf/key-bindings.zsh

_fvim() {
  return "abc"
  #local cmd="${FZF_CTRL_T_COMMAND:-"command find -L . -mindepth 1 \\( -path '*/\\.*' -o -fstype 'sysfs' -o -fstype 'devfs' -o -fstype 'devtmpfs' -o -fstype 'proc' \\) -prune \
  #  -o -type f -print \
  #  -o -type d -print \
  #  -o -type l -print 2> /dev/null | cut -b3-"}"
  #setopt localoptions pipefail no_aliases 2> /dev/null
  #local item
  #eval "$cmd" | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS $FZF_CTRL_T_OPTS" $(__fzfcmd) -m "$@" | while read item; do
  #  echo -n "${(q)item} "
  #done
  #local ret=$?
  #echo
  #return $ret
}

#zle -C _fvim
#bindkey -M vicmd '^O' _fvim 
#bindkey -M viins '^O' _fvim
#bindkey -M emacs '^O' _fvim


#export RPROMPT="%{$fg[blue]%}[INSERT]%{$reset_color%}"
## Callback for vim mode change
#function zle-keymap-select () {
#    # Only supported in these terminals
#    if [ "$TERM" = "xterm-256color" ] || [ "$TERM" = "st" ] || [ "$TERM" = "screen-256color" ]; then
#        if [ $KEYMAP = vicmd ]; then
#            # Command mode
#            export RPROMPT="%{$fg[green]%}[NORMAL]%{$reset_color%}"
#
#            # Set block cursor
#            echo -ne '\e[1 q'
#        else
#            # Insert mode
#            export RPROMPT="%{$fg[blue]%}[INSERT]%{$reset_color%}"
#
#            # Set beam cursor
#            echo -ne '\e[5 q'
#        fi
#    fi
#
#    if typeset -f prompt_pure_update_vim_prompt_widget > /dev/null; then
#        # Refresh prompt and call Pure super function
#        prompt_pure_update_vim_prompt_widget
#    fi
#}
#
## Bind the callback
zle -N zle-keymap-select


# Reduce latency when pressing <Esc>
export KEYTIMEOUT=1

#export KEYTIMEOUT=1 #xtra option for vim keys
zstyle :compinstall filename '/home/maxwell/.zshrc'

autoload -Uz compinit #zshrc autocompletion
compinit
# Enable colors and change prompt:
autoload -U colors && colors
PS1="%B%{$fg[yellow]%}[%{$fg[magenta]%}%n%{$fg[green]%}@%{$fg[blue]%}%M %{$fg[red]%}%~%{$fg[yellow]%}]%{$reset_color%}$%b "

[ -e "$HOME/.zshrc_extra" ] && source "$HOME/.zshrc_extra" #load platform specifcs 
[ -e "$HOME/.config/sh/shrc" ] && source "$HOME/.config/sh/shrc" #load alias and exports 
[ -e "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] && source "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[ -e "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && source "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" && bindkey '^ ' autosuggest-accept
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#46ff00,bg=black,bold,underline"
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
#

#improved help - see arch wiki zsh article
autoload -Uz run-help
(( ${+aliases[run-help]} )) && unalias run-help
alias help=run-help
autoload -Uz run-help-git run-help-ip run-help-openssl run-help-p4 run-help-sudo run-help-svk run-help-svn

#emacs vterm stuff:
vterm_printf(){
    if [ -n "$TMUX" ] && ([ "${TERM%%-*}" = "tmux" ] || [ "${TERM%%-*}" = "screen" ] ); then
        # Tell tmux to pass the escape sequences through
        printf "\ePtmux;\e\e]%s\007\e\\" "$1"
    elif [ "${TERM%%-*}" = "screen" ]; then
        # GNU screen (screen, screen-256color, screen-256color-bce)
        printf "\eP\e]%s\007\e\\" "$1"
    else
        printf "\e]%s\e\\" "$1"
    fi
}

if [[ "$INSIDE_EMACS" = 'vterm' ]]; then
    alias clear='vterm_printf "51;Evterm-clear-scrollback";tput clear'
fi
vterm_prompt_end() {
    vterm_printf "51;A$(whoami)@$(hostname):$(pwd)";
}
setopt PROMPT_SUBST
PROMPT=$PROMPT'%{$(vterm_prompt_end)%}'
