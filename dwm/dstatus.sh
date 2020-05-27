#!/bin/sh
while true; do
    if [ "$(echo "$(date +%s)%5" | bc)" -eq "0" ]; then
        battery="BAT: $(acpi | grep 'harg' | tr ' ' '\n' | awk '/%/ {print}' | sed s/,//)"
        network="NET: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4,"[",$2,"]"}') $(nmcli device wifi | awk '/\*/ {print $9}')"

    fi
    case $dotfiles_tag in 
        thinkpad)
                    OPT="$battery, $network"
                    ;;
        *)  
                    OPT="NO TAG"
                    ;;
    esac
    xsetroot -name "$(date +%a-%d-%b-%R) $OPT"
	sleep 1
done

