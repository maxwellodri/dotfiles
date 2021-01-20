#!/bin/sh

poll_network() {
    command -v nmcli &>/dev/null && network="🌐: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4}') $(nmcli device wifi | awk '/\*/ {print $9}')" && [ $network = "🌐:" ] && network="🌐: NONE"
    echo "$network"
}
poll_battery() { 
    battery="🔋: $(acpi | grep 'harg' | tr ' ' '\n' | awk '/%/ {print}' | sed s/,//)"
    echo "$battery"
}

poll_packages() {
    command -v yay &>/dev/null && package="📦: $(pacman -Qu | wc -l)/$(yay -Qmu | wc -l)" #every hour on the hour poll for number of official and aur packages via yay
    echo "$package"
}

battery="$(poll_battery)"
network="$(poll_network)"
packages="$(poll_packages)"

while true; do
    if [ "$(echo "$(date +%s)%5" | bc)" -eq "0" ]; then
        battery="$(poll_battery)"
        network="$(poll_network)"
    fi

    [ $(date +%M) -eq "0" ] && packages="$(poll_packages)"
    case $dotfiles_tag in 
        thinkpad)
                    OPT="$battery, $network"
                    ;;
        pc) 
                    OPT="$packages, $network"
                    ;;
        *)  
                    OPT="NO TAG"
                    ;;
    esac
    xsetroot -name "🕒 $(date +%a-%d-%b-%R) $OPT"
	sleep 1
done



Hello () {
   echo "Hello World $1 $2"
   return 10
}

