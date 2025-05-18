#!/bin/bash

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_NAME=$(basename "$SCRIPT_PATH")

# Handle restart functionality
if [ "$1" == "--restart" ]; then
    echo "Restarting $SCRIPT_NAME..."
    
    # Get our own PID to exclude
    CURRENT_PID=$$
    
    # Instead of starting a new instance immediately, start it in a subshell
    # that waits for old instances to be killed
    (
        # Wait a moment to let the parent script kill other instances
        sleep 1
        
        # Now start a fresh instance
        exec "$SCRIPT_PATH" >/dev/null 2>&1
    ) &
    
    SUBSHELL_PID=$!
    echo "Created subshell with PID: $SUBSHELL_PID"
    
    # Collect all running instances except grep
    ps_output=$(ps -eo pid,cmd | grep "$SCRIPT_NAME" | grep -v grep)
    
    echo "Current running instances:"
    echo "$ps_output"
    
    # Process each line
    IFS=$'\n' read -rd '' -a processes <<< "$ps_output"
    
    for process in "${processes[@]}"; do
        pid=$(echo "$process" | awk '{print $1}')
        cmd=$(echo "$process" | cut -d' ' -f2-)
        
        # Skip our current process and the subshell
        if [ "$pid" = "$CURRENT_PID" ] || [ "$pid" = "$SUBSHELL_PID" ]; then
            echo "Skipping process: $pid (current process or new subshell)"
            continue
        fi
        
        # Check for script execution patterns
        if [[ "$cmd" == "$SCRIPT_PATH"* ]] || 
           [[ "$cmd" == "./$SCRIPT_NAME"* ]] || 
           [[ "$cmd" == *"/bash $SCRIPT_PATH"* ]] || 
           [[ "$cmd" == *"/bash ./$SCRIPT_NAME"* ]] || 
           [[ "$cmd" == *"/sh $SCRIPT_PATH"* ]] || 
           [[ "$cmd" == *"/sh ./$SCRIPT_NAME"* ]] || 
           [[ "$cmd" == "bash $SCRIPT_NAME"* ]] || 
           [[ "$cmd" == "sh $SCRIPT_NAME"* ]] || 
           [[ "$cmd" == *"setsid "?*"$SCRIPT_NAME"* ]] || 
           [[ "$cmd" == *"nohup "?*"$SCRIPT_NAME"* ]]; then
            
            echo "Killing old instance with PID: $pid and its children"
            # Kill children first
            pkill -TERM -P $pid 2>/dev/null
            # Then kill the parent
            kill $pid 2>/dev/null
        else
            echo "Skipping non-execution process: $pid - $cmd"
        fi
    done
    
    exit 0
fi
cleanup() {
    echo "Program was killed. Cleaning up..."
    xsetroot -name "😠"
}

# Trap exit signal
trap cleanup EXIT

script_directory=$(dirname "$0")
package_file="$script_directory/package_file.txt"
network_touch="$script_directory/network_touch.txt"

poll_network() {
    command -v nmcli &>/dev/null && network="🌐: $(nmcli device | awk '!/disconnected/&&/connected/ {print $4}') $(nmcli device wifi | awk '/\*/ {print $9}')" && [ "$network" = "🌐:" ] && network="🌐: NONE"
    echo "Current network: $network"
}
poll_battery() { 
    eval "$(grep -E '(export dotfiles=|export src=)' "$HOME/.zshrc_extra")"
    [ -v dotfiles ] && python "$dotfiles/dwm/poll_battery.py" 2>/dev/null
}

wireguard_poll() {
    wireguard_runner --query >/dev/null && echo " 🔒✅" || echo " 🔒❎"
}
docker_watch() {
    echo " 🐳: $([ -e "$XDG_CACHE_DIR/dotfiles/dockerup.update" ] && wc -l "$XDG_CACHE_DIR/dotfiles/dockerup.update" | awk '{print $1}' || echo "0")|$(docker ps | tail -n +2 | wc -l)"
}

async_poll_packages() {
    current_time=$(date +%s)
    if [ ! -f "$package_file" ] || [ $((current_time - $(stat -c %Y "$package_file" 2>/dev/null || echo 0))) -gt 180 ]; then
        touch "$package_file" 
        (exec -a "async_poll_packages_dstatus" bash -c "checkupdates | wc -l > \"$package_file\"") &
    else
        return
    fi
}

poll_timew() {
    command -v timew > /dev/null || { echo "#"; return; }
    if timew > /dev/null; then
      duration=$(timew | grep Total | awk '{print $2}')
      formatted_duration="$(echo "$duration" | cut -d: -f1,2)"
      echo "$formatted_duration"
    else
      echo "#"
    fi
}

xsetroot -name "🥹"

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
            command -v timew && timew stop 
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
            screen_resolution=$(xrandr --listmonitors | grep -F '*' | awk '{print $3}' | awk -F'[x/+]' '{print $1, $3}')
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

async_check_internet() {
    (exec -a "async_check_internet_dstatus" bash -c "
        ping -c 1 cia.gov >/dev/null 2>&1
        if [ \$? -eq 0 ]; then
            echo \"yes\" > \"$network_touch\"
        else
            echo \"no\" > \"$network_touch\"
        fi
    ") &
}

[ -f "$network_touch" ] && rm "$network_touch"

#battery="$(poll_battery)"
battery=""
#network="$(poll_network)"
network=""
packages="?"
async_poll_packages
async_check_internet
timedata=""
timew_timer="$(poll_timew)"
internet="?"

counter=0
eval "$(grep 'export dotfiles_tag' "$HOME/.zprofile")"
[ -z "$dotfiles_tag" ] && echo "dotfiles_tag envar is not set in .zprofile?"

while true; do
    case "$dotfiles_tag" in 
        hackerman)
            OPT="$(docker_watch) $(poll_battery)"
                    ;;
        pc) 
            OPT="$(docker_watch)$(wireguard_poll)"
                    ;;
        *)  
                    OPT=" NO TAG"
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
        async_check_internet
	fi
    counter=$((counter+1))

    [ "$(date +%M)" -eq "0" ] && async_poll_packages
    if [ "$(date +%M)" -eq "05" ] || [ "$(date +%M)" -eq "35" ]; then
        [ -f "$package_file" ] && packages="$(<"$package_file")" || packages="?"
    fi



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

    cpu_usage=$(top -b -n 2 | grep Cpu | sed 's/:/ /g' | awk '{printf "CPU Load:%7.0f\n", $(NF-13) + $(NF-15)}' | sed -n '2 p' | awk '{print $3}')
    rounded_cpu=$(( $cpu_usage <  99 ? $cpu_usage : 99 ))
    command -v get_reminders.sh > /dev/null && reminders="🧐: $(get_reminders.sh --count)" || reminders="😠: 0"
    xsetroot -name "$timedata $reminders 🕒: $(date +%a-%d-%b-%R) 🧠: $(sh memory_checker)% 🤔:$(printf "%2d" "$rounded_cpu")% 🌏: $internet 🚚: $packages$OPT"

	sleep 0.25s
done
