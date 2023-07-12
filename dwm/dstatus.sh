#!/bin/bash
xsetroot -name "🥹"

script_directory=$(dirname "$0")
package_file="$script_directory/package_file.txt"

poll_network() {
    command -v nmcli &>/dev/null && network="🌐: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4}') $(nmcli device wifi | awk '/\*/ {print $9}')" && [ $network = "🌐:" ] && network="🌐: NONE"
    echo "Current network: $network"
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
    echo $(checkupdates | wc -l) > "$package_file"
}

poll_timew() {
    if timew > /dev/null; then
      duration=$(timew | grep Total | awk '{print $2}')
      formatted_duration=$(echo $duration | cut -d: -f1,2)
      echo "$formatted_duration"
    else
      echo "#"
    fi
}


prev_notify="0:00"
prev_notify_long="0:00"
notify_duration=1  # Duration in minutes
long_notify_duration=60  # Duration in minutes

try_notify() {
    echo "$timew_timer, $prev_notify"
    if [[ "$timew_timer" != "0:00" ]] && [[ "$timew_timer" != "$prev_notify" ]]; then
        #Parse the current time elapsed and the prev notify time into minutes:

        # Split hours and minutes based on the delimiter ":"
        hours=${timew_timer%%:*}
        minutes=${timew_timer#*:}
        
        # Convert hours to minutes and add the remaining minutes
        current_total_minutes=$(($hours*60 + $minutes))

        # Split hours and minutes based on the delimiter ":"
        hours=${prev_notify%%:*}
        minutes=${prev_notify#*:}
        
        # Convert hours to minutes and add the remaining minutes
        prev_total_minutes=$(($hours*60 + $minutes))

        difference=$(( current_total_minutes - prev_total_minutes ))
        if [ "$difference" -ge "$long_notify_duration" ]; then
            notify-send -u critical -t 60000 "Long Break - elapsed: $elapsed_time " -a "BreakReminder"
            sleep 0.1
            # Obtain the window ID of the notify-send window
            notify_send_window_id=$(xdotool search --class "Dunst")
            # Calculate the screen and window dimensions for centering
            screen_resolution=$(xrandr --listmonitors | grep '*' | awk '{print $3}' | awk -F'[x/+]' '{print $1, $3}')
            read -r screen_width screen_height <<< "$screen_resolution"         
            
            window_width=800
            window_height=400
            move_x=$((screen_width - window_width / 2))
            move_y=$((screen_height - window_height ))
            xdotool windowmove "$notify_send_window_id" "$move_x" "$move_y"
            xdotool windowsize "$notify_send_window_id" "$window_height" "$window_width" #dunst wont allow resizing windows

            prev_notify_long="$timew_timer"
            prev_notify="$timew_timer"
        elif [ "$difference" -ge "$notify_duration" ]; then
            notify-send "You've been working for $elapsed_time seconds. Take a short break!"
            prev_notify="$timew_timer"
        fi
    fi
}

#battery="$(poll_battery)"
battery=""
#network="$(poll_network)"
network=""
packages=""
timedata=""
#packages="$(poll_packages)"
timew_timer="$(poll_timew)"
#cpu
#packages="$(poll_packages)"
#
counter=0
while true; do
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
    xsetroot -name "$timedata 🕒 $(date +%a-%d-%b-%R) 🧠: $(sh memory_checker)% 🤔:$(printf "%2d" "$rounded")% 🚚: $packages$OPT"
    #cpu_usage=$(echo "100-$(mpstat --dec=0 | grep all | awk '{print $12}')" | bc)
    timew_timer="$(poll_timew)"
    if [ "$(echo "$(date +%s)%1" | bc)" -eq "0" ]; then #every 2 seconds poll these:
        timew_timer="$(poll_timew)"
        if [[ "$timew_timer" == "#" ]]; then
          timedata="🙅"
        else
          timedata="🧐 $timew_timer"
        fi
        echo "polling time: $timew_timer"
        #battery="$(poll_battery)"
        #network="$(poll_network)"
    fi
	if (( counter % 4 == 0 )); then
		try_notify
	fi
    counter=$((counter+1))
    echo $counter

    if [ "$(echo "$(date +%s)%60" | bc)" -eq "0" ]; then #every 60 seconds poll these:
        packages="$(poll_packages)"
    fi

    [ $(date +%M) -eq "0" ] && poll_packages &

    if [ -f "$package_file" ]; then
        packages=$(cat "$package_file")
        echo "Updated packages"
        rm "$package_file"  # Clean up the shared data file
    fi
    cpu_usage=$(top -b -n 2 | grep Cpu | sed 's/:/ /g' | awk '{printf "CPU Load:%7.0f\n", $(NF-13) + $(NF-15)}' | sed -n '2 p' | awk '{print $3}')
    rounded=$(( $cpu_usage <  99 ? $cpu_usage : 99 ))

	sleep 0.25s
done
