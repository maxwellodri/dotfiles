#!/bin/bash

<<<<<<< HEAD
NOTIFY_TIMEOUT=2000

if ! pacman -Qi wireguard-tools >/dev/null 2>&1; then
    exit 0
fi

=======
NOTIFY_SEND=false
NOTIFY_TIMEOUT=2000

>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
get_active_interfaces() {
    wg show interfaces 2>/dev/null | tr ' ' '\n' | grep -v '^ '|| true
}

<<<<<<< HEAD
get_interface_label() {
    local config_path="$1"
    local label
    label=$(run_elevated grep "^#Label:" "$config_path" 2>/dev/null | sed 's/^#Label:[[:space:]]*//' | head -n1)
=======
if [ "$1" = "--query" ]; then
    active_interfaces=$(get_active_interfaces)
    if [ -n "$active_interfaces" ]; then
        echo "Wireguard is on"
        exit 0
    else
        echo "Wireguard is off"
        exit 1
    fi
fi

if ! pacman -Qi wireguard-tools >/dev/null 2>&1; then
    exit 0
fi

get_interface_label() {
    local config_path="$1"
    local label
    label=$(run_elevated awk '/^#Label:/ && !/PrivateKey/ && !/PreSharedKey/ && !/[A-Za-z0-9+\/]{43}=/ {print; exit}' "$config_path" 2>/dev/null | sed 's/^#Label:[[:space:]]*//')
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
    echo "$label"
}

run_elevated() {
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        pkexec "$@"
    else
        sudo "$@"
    fi
}

<<<<<<< HEAD
if [ "$1" = "--query" ]; then
    active_interfaces=$(get_active_interfaces)
    if [ -n "$active_interfaces" ]; then
        exit 0
    else
        exit 1
    fi
fi

=======
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
available_output=$(run_elevated find /etc/wireguard -maxdepth 1 -name "*.conf" -type f)
discovery_exit_code=$?

if [ $discovery_exit_code -ne 0 ]; then
    notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn-error "No WireGuard configs found" "/etc/wireguard directory access failed"
    exit 1
fi

declare -A interface_labels
available_interfaces=()
while IFS= read -r config_path; do
    if [ -n "$config_path" ]; then
        interface=$(basename "$config_path" .conf)
        label=$(get_interface_label "$config_path")
        available_interfaces+=("$interface")
        if [ -n "$label" ]; then
            interface_labels["$interface"]="$label"
        fi
    fi
done <<< "$available_output"

if [ ${#available_interfaces[@]} -eq 0 ]; then
    notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn-error "No WireGuard configs found" "No .conf files in /etc/wireguard/"
    exit 1
fi

active_interfaces=$(get_active_interfaces)

none="none"
options=()
<<<<<<< HEAD
options+=("$none")
=======
if [ -z "$active_interfaces" ]; then
    options+=("$none (active)")
else
    options+=("$none")
fi
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)

for interface in "${available_interfaces[@]}"; do
    display_name="$interface"
    if [ -n "${interface_labels[$interface]}" ]; then
        display_name="$interface [${interface_labels[$interface]}]"
    fi
    
    if echo "$active_interfaces" | grep -q "^$interface$"; then
        options+=("$display_name (active)")
    else
        options+=("$display_name")
    fi
done

selected=$(printf '%s\n' "${options[@]}" | dmenu -c -l 10 -i -p "Select WireGuard interface:" | awk '{print $1}')

if [ -z "$selected" ]; then
    exit 0
fi

if [ "$selected" = "$none" ]; then
    if [ -n "$active_interfaces" ]; then
        success_count=0
        for interface in $active_interfaces; do
<<<<<<< HEAD
            if run_elevated wg-quick down "$interface"; then
                notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard disconnected" "Interface: $interface"
=======
            if run_elevated wg-quick down "$interface" >/dev/null 2>&1; then
                if [ "$NOTIFY_SEND" = "true" ]; then
                    notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard disconnected" "Interface: $interface"
                fi
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
                ((success_count++))
            else
                notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn-offline "WireGuard failed to disconnect" "Interface: $interface"
            fi
        done
    else
<<<<<<< HEAD
        notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard" "No active interfaces to disconnect"
=======
        if [ "$NOTIFY_SEND" = "true" ]; then
            notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard" "No active interfaces to disconnect"
        fi
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
    fi
    exit 0
fi

interface="$selected"

if echo "$active_interfaces" | grep -q "^$interface$"; then
<<<<<<< HEAD
    notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard" "Interface $interface is already active"
=======
    if [ "$NOTIFY_SEND" = "true" ]; then
        notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard" "Interface $interface is already active"
    fi
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
    exit 0
fi

if [ -n "$active_interfaces" ]; then
    for active_interface in $active_interfaces; do
<<<<<<< HEAD
        run_elevated wg-quick down "$active_interface" || true
    done
fi

if run_elevated wg-quick up "$interface"; then
    notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard connected" "Interface: $interface"
=======
        run_elevated wg-quick down "$active_interface" >/dev/null 2>&1 || true
    done
fi

if run_elevated wg-quick up "$interface" >/dev/null 2>&1; then
    if [ "$NOTIFY_SEND" = "true" ]; then
        notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn "WireGuard connected" "Interface: $interface"
    fi
>>>>>>> f132c36 (add wg_switcher script incl necessary config changes)
else
    notify-send -r 9901 -t $NOTIFY_TIMEOUT -i network-vpn-error "WireGuard failed to connect" "Interface: $interface - Check system logs"
fi
