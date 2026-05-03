#!/usr/bin/env bash
set -euo pipefail

. "${XDG_CONFIG_HOME:-$HOME/.config}/sh/shutil.sh"

NOTIFY_TIMEOUT=2000
WG_DIR="/etc/wireguard"

dmenu=$(get_dmenu)
has_display=false
[[ "$dmenu" != "fzf" ]] && has_display=true

check_kernel

if ! command -v wg >/dev/null 2>&1; then
    notify network-vpn-error "WireGuard" "wireguard-tools not installed"
    exit 1
fi

get_active_interfaces() {
    wg show interfaces 2>/dev/null | tr ' ' '\n' || true
}

notify() {
    local icon="$1" title="$2" body="${3:-}"
    if [[ "$has_display" == true ]]; then
        notify-send -r 9901 -t "$NOTIFY_TIMEOUT" -i "$icon" "$title" "$body" 2>/dev/null || true
    else
        echo "$title${body:+: $body}" >&2
    fi
}

if [[ ${1:-} == "--query" ]]; then
    if [[ -n $(get_active_interfaces) ]]; then
        echo "Wireguard is on"
        exit 0
    else
        echo "Wireguard is off"
        exit 1
    fi
fi

action_connect=""
action_disconnect=false
case "${1:-}" in
    --connect)
        action_connect="${2:-}"
        if [[ -z "$action_connect" ]]; then
            echo "Usage: $0 --connect <interface>" >&2
            exit 1
        fi
        ;;
    --disconnect)
        action_disconnect=true
        ;;
esac

config_output=$(run_elevated bash -c '
    for f in /etc/wireguard/*.conf; do
        [ -f "$f" ] || continue
        iface=$(basename "$f" .conf)
        label=$(grep "^#Label:" "$f" 2>/dev/null | head -1 | sed "s/^#Label:[[:space:]]*//")
        if [ -n "$label" ]; then
            echo "$iface|$label"
        else
            echo "$iface|"
        fi
    done
') || true

declare -A interface_labels
available_interfaces=()
while IFS='|' read -r iface label; do
    [[ -z "$iface" ]] && continue
    available_interfaces+=("$iface")
    if [[ -n "$label" ]]; then
        interface_labels["$iface"]="$label"
    fi
done <<< "$config_output"

if [[ ${#available_interfaces[@]} -eq 0 ]]; then
    notify network-vpn-error "No WireGuard configs found" "No .conf files in $WG_DIR/"
    exit 1
fi

active_interfaces=$(get_active_interfaces)

disconnect_all() {
    local active="$1"
    [[ -z "$active" ]] && return 0
    while IFS= read -r iface; do
        [[ -z "$iface" ]] && continue
        run_elevated wg-quick down "$iface" || \
            notify network-vpn-offline "WireGuard failed to disconnect" "Interface: $iface"
    done <<< "$active"
}

if [[ "$action_disconnect" == true ]]; then
    disconnect_all "$active_interfaces"
    exit 0
fi

if [[ -n "$action_connect" ]]; then
    disconnect_all "$active_interfaces"
    if run_elevated wg-quick up "$action_connect"; then
        notify network-vpn "WireGuard connected" "Interface: $action_connect"
    else
        notify network-vpn-error "WireGuard failed to connect" "Interface: $action_connect"
        exit 1
    fi
    exit 0
fi

none="none"
options=()
if [[ -z "$active_interfaces" ]]; then
    options+=("$none (active)")
else
    options+=("$none")
fi

for interface in "${available_interfaces[@]}"; do
    display_name="$interface"
    if [[ -n "${interface_labels[$interface]:-}" ]]; then
        display_name="$interface [${interface_labels[$interface]}]"
    fi
    if echo "$active_interfaces" | grep -q "^${interface}$"; then
        options+=("$display_name (active)")
    else
        options+=("$display_name")
    fi
done

if [[ "$dmenu" == "fzf" ]]; then
    selected=$(printf '%s\n' "${options[@]}" | fzf --prompt="WireGuard interface: " | awk '{print $1}')
else
    selected=$(printf '%s\n' "${options[@]}" | "$dmenu" -c -l 10 -i -p "Select WireGuard interface:" | awk '{print $1}')
fi
[[ -z "$selected" ]] && exit 0

if [[ "$selected" == "$none" ]]; then
    disconnect_all "$active_interfaces"
    exit 0
fi

if echo "$active_interfaces" | grep -q "^${selected}$"; then
    notify network-vpn "WireGuard" "Interface $selected is already active"
    exit 0
fi

disconnect_all "$active_interfaces"

if run_elevated wg-quick up "$selected"; then
    notify network-vpn "WireGuard connected" "Interface: $selected"
else
    notify network-vpn-error "WireGuard failed to connect" "Interface: $selected - Check system logs"
    exit 1
fi
