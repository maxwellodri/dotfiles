#!/bin/bash

poll_network() {
    command -v nmcli &>/dev/null && network="🌐: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4}') $(nmcli device wifi | awk '/\*/ {print $9}')" && [ $network = "🌐:" ] && network="🌐: NONE"
    echo "$network"
}
poll_battery() { 
    #battery="🔋: $(acpi | awk '{print $4}' | head -n1 | sed s/,//)"
    battery="🔋: $(echo $(acpi | awk '{print $4}' | tr -d , | awk -v RS=  '{$1=$1}1' | awk '{print $1 "+" $2 }' | tr -d % | bc | tr -d '\n'; echo "/2") | bc)%"
    echo "$battery"
}

poll_packages() {
    echo $(checkupdates | wc -l)
}

battery="$(poll_battery)"
network="$(poll_network)"
packages="$(poll_packages)"
#packages="$(poll_packages)"

while true; do

    [ $(date +%M) -eq "0" ] && packages="$(poll_packages)"
    case $dotfiles_tag in 
        thinkpad)
                    OPT=" $battery, $network"
                    ;;
        pc) 
                    OPT="" #" $packages, $network"
                    ;;
        *)  
                    OPT="NO TAG"
                    ;;
    esac
    xsetroot -name "🕒 $(date +%a-%d-%b-%R) 🧠: $(sh $dotfile/scripts/memory_checker)% 🚚: $packages$OPT"
	sleep 1
    if [ "$(echo "$(date +%s)%2" | bc)" -eq "0" ]; then #every 2 seconds poll these:
        battery="$(poll_battery)"
        network="$(poll_network)"
        continue 
    fi
    if [ "$(echo "$(date +%s)%300" | bc)" -eq "0" ]; then #every 300 seconds poll these:
        packages="$(poll_packages)"
        continue 
    fi
done
