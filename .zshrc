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
HISTSIZE=5000
HISTFILE=~/.cache/histfile
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

#ignore case for completions:
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# fg-bg toggle via c-z
function fg-bg { 
    if [[ $#BUFFER -eq 0 ]]; then 
        BUFFER="fg"
        zle accept-line
    else
        zle push-input
    fi
}

zle -N fg-bg
bindkey '^z' fg-bg

declare -A venvs=(
    #["tortoise"]="~/source/tortoise/"
    # add more directories and virtual environment paths here
)

function chpwd() {
    emulate -L zsh
    for dir venv in ${(kv)venvs}; do
        if [[ "$PWD" == "$dir"* ]]; then
            source "$venv/$dir/bin/activate"
            break
        else
            deactivate 2>/dev/null
        fi
    done
}

#(cat ~/.cache/wal/sequences &) #pywal
[ -e ~/.cache/wal/colors-tty.sh ] && source ~/.cache/wal/colors-tty.sh
[ -e ~/.secrets ] && source ~/.secrets
[ -e /etc/profile.d/google-cloud-sdk.sh ] && source /etc/profile.d/google-cloud-sdk.sh
[ -e ~/.local/share/mdbook_completions.zsh ] && source  ~/.local/share/mdbook_completions.zsh 
setopt autocd #type name of dir to cd
unsetopt beep #no beep
bindkey -v #vim keys

#ignore completions for cargo clean
_my_cargo_completion () {
  # Get the current word being completed
  local word="${COMP_WORDS[COMP_CWORD]}"

  # If the current word is "clean", don't suggest it
  if [[ "$word" == "clean" ]]; then
    return
  fi

  # Otherwise, use the default completion for `cargo`
  _arguments '*: :_cargo'
}
detoxx() {
    new_files=$(detox -n * 2>&1 | grep "Cannot rename.*\sto\s" | awk -F'Cannot rename | to ' '{print $2}' | awk '{sub(/:$/, ""); print}')
    detox -n * 2>&1 | grep  "Cannot rename.*\sto\s" | awk '{print $(NF-3)}' | awk '{sub(/:$/,"")}1' | xargs -r rm -rf
    [ ! -z "$new_files" ] && detox "$new_files" || echo "Nothing to detox"
}
debug_detoxx() {

    # Run detox in dry-run mode and capture the old and new filenames
    new_files=$(detox -n * 2>&1 | grep "Cannot rename.*\sto\s" | awk -F'Cannot rename | to ' '{print $2}' | awk '{sub(/:$/, ""); print}')
    old_files=$(detox -n * 2>&1 | grep  "Cannot rename.*\sto\s" | awk '{print $(NF-3)}' | awk '{sub(/:$/,"")}1')

    # Print old and new file paths instead of deleting
    echo "Old files:"
    echo "$old_files"

    echo "New files:"
    echo "$new_files"
}

fdt() {
    fd "$1" -0 | xargs -0 touch
}

#fpath=(~/.zsh/completion /usr/local/share/zsh/site-functions /usr/share/zsh/site-functions /usr/share/zsh/5.9/functions)
autoload -Uz compinit && compinit
compdef _my_cargo_completion cargo

#set yanking to yank to system clipboard
function vi-yank-xclip {
    zle vi-yank
   echo "$CUTBUFFER" | xclip -i #xclip is obviously X11/Linux only
}
zle -N vi-yank-xclip
bindkey -M vicmd 'y' vi-yank-xclip

bindkey '^n' history-search-forward

source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

function _fuzzy_vim {
    # Execute the script and capture the output
    local output="$($HOME/bin/fuzzy_vim)"
    local dir_output=""
    [ -d "$output" ] && dir_output="$output"

    zle clear_input
    #echo "Output: $output"
    if [[ -d "$output" ]]; then #if directory
        cd "$output"
    elif [[ -f "$output" ]]; then #if file
        dir="$(dirname $output)"
        if git --git-dir "$dir" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
            cd $(git rev-parse --show-toplevel)
        else
            cd "$dir"
        fi
    else
        #do nothing if nothing was selceted from output
    fi

    BUFFER=""
    zle accept-line
}

function _vim_in_dir {
    zle clear_input
    vim .
    BUFFER=""
    zle accept-line
}

function _sterm {
    # Execute the command in background without affecting current line
    command setsid -f st -d . 1&>/dev/null
}

function _git_root {
    zle clear-input
    BUFFER="cd $(git rev-parse --show-toplevel)"
    zle accept-line
}

sw_widget() {
   local output
   output=$(sw)
   [[ -n "$output" ]] && eval "$output" && zle reset-prompt
}

sw_find() {
   local output
   output=$(sw find)
   [[ -n "$output" ]] && eval "$output" && zle reset-prompt
}
zle -N sw_widget
bindkey -M vicmd '^F' sw_widget
bindkey -M viins '^F' sw_widget

stty -ixon

zle -N sw_find
bindkey -M vicmd '^S' sw_find
bindkey -M viins '^S' sw_find

zle -N _vim_in_dir
bindkey -M viins '^X' _vim_in_dir
bindkey -M vicmd '^X' _vim_in_dir

zle -N _git_root
bindkey -M viins '^G' _git_root
bindkey -M vicmd '^G' _git_root

zle -N _sterm
bindkey -M vicmd '^T' _sterm
bindkey -M viins '^T' _sterm #overrides default fzf/key-bindings.zsh

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

[ -e "$HOME/.config/sh/shrc" ] && source "$HOME/.config/sh/shrc" #load alias and exports 
[ -e "$HOME/.zshrc_extra" ] && source "$HOME/.zshrc_extra" #load platform specifcs 
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

lazy_conda_aliases=('python' 'conda')

load_conda() {
  for lazy_conda_alias in $lazy_conda_aliases
  do
    unalias $lazy_conda_alias
  done

  __conda_prefix="$HOME/.miniconda3" # Set your conda Location

  # >>> conda initialize >>>
  __conda_setup="$("$__conda_prefix/bin/conda" 'shell.bash' 'hook' 2> /dev/null)"
  if [ $? -eq 0 ]; then
      eval "$__conda_setup"
  else
      if [ -f "$__conda_prefix/etc/profile.d/conda.sh" ]; then
# . "$__conda_prefix/etc/profile.d/conda.sh"  # commented out by conda initialize
      else
          export PATH="$__conda_prefix/bin:$PATH"
      fi
  fi
  unset __conda_setup
  # <<< conda initialize <<<

  unset __conda_prefix
  unfunction load_conda
}

for lazy_conda_alias in $lazy_conda_aliases
do
  alias $lazy_conda_alias="load_conda && $lazy_conda_alias"
done

eval "$(direnv hook zsh)"
