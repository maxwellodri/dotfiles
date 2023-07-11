#!/bin/bash

poll_network() {
    command -v nmcli &>/dev/null && network="🌐: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4}') $(nmcli device wifi | awk '/\*/ {print $9}')" && [ $network = "🌐:" ] && network="🌐: NONE"
    echo "$network"
}
poll_battery() { 
    #battery="🔋: $(acpi | awk '{print $4}' | head -n1 | sed s/,//)"
    battery_icon="🔋"
    [ -n $(acpi | awk '{print $3}' | grep -i charging) ] && battery_icon="⚡"
    battery="$battery_icon: $(echo $(acpi | awk '{print $4}' | tr -d , | tr -d %))" #| awk -v RS=  '{$1=$1}1' | awk '{print $1 "+" $2 }' | tr -d % | bc | tr -d '\n'; echo "/2") | bc)%"
    echo "$battery"
}
#poll_network() {
#    command -v nmcli &>/dev/null && network="🌐: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4}') $(nmcli device wifi | awk '/\*/ {print $9}')" && [ $network = "🌐:" ] && network="🌐: NONE"
#    echo "$network"
#}
#poll_battery() { 
#    #battery="🔋: $(acpi | awk '{print $4}' | head -n1 | sed s/,//)"
#    battery="🔋: $(echo $(acpi | awk '{print $4}' | tr -d , | awk -v RS=  '{$1=$1}1' | awk '{print $1 "+" $2 }' | tr -d % | bc | tr -d '\n'; echo "/2") | bc)%"
#    echo "$battery"
#}

poll_packages() {
    echo $(checkupdates | wc -l)
}

poll_timew() {
    if timew > /dev/null; then
      duration=$(timew | grep Total | awk '{print $2}')
      formatted_duration=$(echo $duration | cut -d: -f1,2)
      echo "🧐 $formatted_duration"
    else
      echo "🙅"
    fi
}

#battery="$(poll_battery)"
battery=""
#network="$(poll_network)"
network=""
packages="$(poll_packages)"
timew_timer="$(poll_timew)"
#cpu
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
    #cpu_usage=$(echo "100-$(mpstat --dec=0 | grep all | awk '{print $12}')" | bc)
    cpu_usage=$(top -b -n 2 | grep Cpu | sed 's/:/ /g' | awk '{printf "CPU Load:%7.0f\n", $(NF-13) + $(NF-15)}' | sed -n '2 p' | awk '{print $3}')
    rounded=$(( $cpu_usage <  99 ? $cpu_usage : 99 ))
    xsetroot -name "$timew_timer 🕒 $(date +%a-%d-%b-%R) 🧠: $(sh memory_checker)% 🤔:$(printf "%2d" "$rounded")% 🚚: $packages$OPT"
	sleep 0.25s
    timew_timer="$(poll_timew)"
    if [ "$(echo "$(date +%s)%1" | bc)" -eq "0" ]; then #every 2 seconds poll these:
        timew_timer="$(poll_timew)"
        #battery="$(poll_battery)"
        #network="$(poll_network)"
        continue 
    fi
    if [ "$(echo "$(date +%s)%60" | bc)" -eq "0" ]; then #every 60 seconds poll these:
        packages="$(poll_packages)"
        continue 
    fi
done
