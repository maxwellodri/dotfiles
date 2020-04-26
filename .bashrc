#!/bin/bash
# _               _              
#| |__   __ _ ___| |__  _ __ ___ 
#| '_ \ / _` / __| '_ \| '__/ __|
#| |_) | (_| \__ \ | | | | | (__ 
#|_.__/ \__,_|___/_| |_|_|  \___|
#

PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}\007"' #$USER@HOSTNAME : WORKNG DIR
stty -ixon #Disable ctrl-s and ctrl-q
set -o vi #literally just 6 letters pepehands

[ -e "$HOME/.config/shrc" ] && source "$HOME/.config/sh/shrc"
[ -e "$HOME/.bashrc_extra" ] && source "$HOME/.bashrc_extra"
                                
