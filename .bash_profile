export PATH="$PATH:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl:/home/maxwell/bin:/home/maxwell/bin"
export PATH="$HOME/.cargo/bin:$PATH"
source /home/maxwell/.bashrc
#below needed for gnome
export GDK_BACKEND=x11
if [[ ! $DISPLAY && $XDG_VTNR -eq 1 ]]; then
    startx /usr/bin/i3
fi

