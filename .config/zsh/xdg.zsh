export XINITRC="$XDG_CONFIG_HOME"/X11/xinitrc
export XSERVERRC="$XDG_CONFIG_HOME"/X11/xserverrc
export OMNISHARPHOME="$XDG_CONFIG_HOME/omnisharp"
export NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/npmrc
export NVM_DIR="$XDG_DATA_HOME"/nvm 
export PYENV_ROOT=$XDG_DATA_HOME/pyenv 
export PYTHON_HISTORY=$XDG_STATE_HOME/python/history
export FFMPEG_DATADIR="$XDG_CONFIG_HOME"/ffmpeg 
export GRADLE_USER_HOME="$XDG_DATA_HOME"/gradle 
export RUSTUP_HOME="$XDG_DATA_HOME"/rustup 
export CARGO_HOME="$XDG_DATA_HOME"/cargo 
export _JAVA_OPTIONS=-Djava.util.prefs.userRoot="$XDG_CONFIG_HOME"/java
export JUPYTER_CONFIG_DIR="$XDG_CONFIG_HOME"/jupyter 
export KDEHOME="$XDG_CONFIG_HOME"/kde 
export WINEPREFIX="$XDG_DATA_HOME"/wine
export W3M_DIR="$XDG_DATA_HOME"/w3m
export VAGRANT_HOME="$XDG_DATA_HOME"/vagrant
export TEXMFVAR="$XDG_CACHE_HOME"/texlive/texmf-var
export NUGET_PACKAGES="$XDG_CACHE_HOME"/NuGetPackages
export NODE_REPL_HISTORY="$XDG_DATA_HOME"/node_repl_history
export DOTNET_CLI_HOME="$XDG_DATA_HOME"/dotnet
export DOCKER_CONFIG="$XDG_CONFIG_HOME"/docker
export CUDA_CACHE_PATH="$XDG_CACHE_HOME"/nv

export AWS_SHARED_CREDENTIALS_FILE="$XDG_CONFIG_HOME"/aws/credentials
export AWS_CONFIG_FILE="$XDG_CONFIG_HOME"/aws/config
export ANDROID_USER_HOME="$XDG_DATA_HOME"/android

alias wget=wget --hsts-file="$XDG_DATA_HOME/wget-hsts"
alias adb='HOME="$XDG_DATA_HOME"/android adb'
