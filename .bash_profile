export PATH="$PATH:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/maxwell/bin:/home/maxwell/bin"
export PATH="$HOME/.cargo/bin:$PATH"
export VK_ICO_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json 
source /home/maxwell/.bashrc
if [[ ! $DISPLAY && $XDG_VTNR -eq 1 ]]; then
    startx /usr/bin/i3
fi

