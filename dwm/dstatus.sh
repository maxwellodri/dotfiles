#!/bin/bash
xsetroot -name "🥹"



cleanup() {
  # Insert your cleanup code here
  echo "Program was killed. Cleaning up..."
  xsetroot -name "😠"
  # Additional commands as needed
}

trap cleanup EXIT

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

async_poll_packages() {
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

idle_threshold_minutes=10
prev_notify="0:00"
prev_notify_long="0:00"
notify_duration=30  # Duration in minutes
long_notify_duration=120  # Duration in minutes
first_try_notify="yes"

try_notify() {
    echo "$timew_timer, $prev_notify"
    if [[ "$timew_timer" != "0:00" ]] && [[ "$timew_timer" != "#" ]]&& [[ "$timew_timer" != "$prev_notify" ]] ; then
        #Parse the current time elapsed and the prev notify time into minutes:

        # Split hours and minutes based on the delimiter ":"
        IFS=":" read -r -a time_parts <<< "$timew_timer"
        hours=$((10#${time_parts[0]}))
        minutes=$((10#${time_parts[1]}))
        
        # Convert hours to minutes and add the remaining minutes
        current_total_minutes=$(($hours*60 + $minutes))

        # Split hours and minutes based on the delimiter ":"
        IFS=":" read -r -a prev_time_parts <<< "$prev_notify"
        prev_hours=$((10#${prev_time_parts[0]}))
        prev_minutes=$((10#${prev_time_parts[1]}))
        if [ "$(($(xprintidle) / 60000 ))" -ge "$idle_threshold_minutes" ]; then
            [ timew ] && timew stop 
        fi
        # Convert hours to minutes and add the remaining minutes
        prev_total_minutes=$(($prev_hours*60 + $prev_minutes))
        difference=$(( current_total_minutes - prev_total_minutes ))
        if [ "$difference" -ge "$long_notify_duration" ]; then
            [ -z "$first_try_notify" ] && notify-send -u critical -t 60000 -a "Long Break Reminder" "Long Break"
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
            first_try_notify=""
        elif [ "$difference" -ge "$notify_duration" ] && [[ "$current_total_minutes" -ge "15" ]]; then
             
            [ -z "$first_try_notify" ] && notify-send -a "Short Break Reminder" "Short Break" #make so the notify doesnt fire as soon as dstatus is started - wait at least $notify_duration mins
            first_try_notify=""
            prev_notify="$timew_timer"
        fi
    fi
}

network_touch="$script_directory/network_touch.txt"
try_internet_connection() {
    ping -c 1 cia.gov >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "yes" > $network_touch
    else
        echo "no" > $network_touch
    fi
}

[ -f "$package_file" ] && rm "$package_file"  # Clean up the shared data file
[ -f "$network_touch" ] && rm "$network_touch"

#battery="$(poll_battery)"
battery=""
#network="$(poll_network)"
network=""
packages="?"
async_poll_packages &
try_internet_connection &
timedata=""
#packages="$(async_poll_packages)"
timew_timer="$(poll_timew)"
internet="?"
#cpu
#packages="$(async_poll_packages)"
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
    #cpu_usage=$(echo "100-$(mpstat --dec=0 | grep all | awk '{print $12}')" | bc)
    timew_timer="$(poll_timew)"
    if [ "$(echo "$(date +%s)%1" | bc)" -eq "0" ]; then #every 2 seconds poll these:
        timew_timer="$(poll_timew)"
    fi

    if [[ "$timew_timer" == "#" ]]; then
        timedata="🙅"
    else
        timedata="🧐: $timew_timer"
    fi


	if (( counter % 4 == 0 )); then
		try_notify
        try_internet_connection &
	fi
    counter=$((counter+1))

    [ $(date +%M) -eq "0" ] && async_poll_packages &


    if [ -f "$network_touch" ]; then
        content=$(<"$network_touch")  # Read the file contents
        if [[ "$content" == "yes" ]]; then
            internet="🥹"
        elif [[ "$content" == "no" ]]; then
            internet="⚠"
        else
            internet="?"
        fi
        rm "$network_touch"
    fi

    if [ -f "$package_file" ]; then
        packages=$(cat "$package_file")
        echo "Updated packages"
        rm "$package_file"  # Clean up the shared data file
    fi

    xsetroot -name "$timedata 🕒: $(date +%a-%d-%b-%R) 🧠: $(sh memory_checker)% 🤔:$(printf "%2d" "$rounded_cpu")% 🌏: $internet 🚚: $packages$OPT"

    cpu_usage=$(top -b -n 2 | grep Cpu | sed 's/:/ /g' | awk '{printf "CPU Load:%7.0f\n", $(NF-13) + $(NF-15)}' | sed -n '2 p' | awk '{print $3}')
    rounded_cpu=$(( $cpu_usage <  99 ? $cpu_usage : 99 ))

	sleep 0.25s
done
