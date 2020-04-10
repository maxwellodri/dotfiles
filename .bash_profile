#!/bin/bash
export PATH="$PATH:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/maxwell/bin:/home/maxwell/bin"
export PATH="$HOME/.cargo/bin:$PATH"
export TERM='terminator'
if [[ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]] ; then
    export VK_ICO_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json 
fi

if [[ -f "$HOME/.bashrc" ]] ; then
    source "$HOME/.bashrc"
fi
if [[ ! $DISPLAY && $XDG_VTNR -eq 1 ]]; then
    exec startx 
fi

function i3ws(){
    #prints current workspace from i3
     i3-msg -t get_workspaces \
  | jq '.[] | select(.focused==true).name' \
  | cut -d"\"" -f2
}


