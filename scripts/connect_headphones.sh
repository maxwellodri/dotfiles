#!/usr/bin/env bash
MAC="24:09:EB:07:E8:60"

# Initialize bluetooth
bluetoothctl power on >/dev/null 2>&1
bluetoothctl agent on >/dev/null 2>&1

show_help() {
    echo "Usage: $(basename "$0") [OPTION]"
    echo ""
    echo "Toggle connection to headphones ($MAC)."
    echo ""
    echo "Options:"
    echo "  --pair    Remove and re-pair the device (use if connection is broken)"
    echo "  --help    Show this help message"
    echo ""
    echo "With no arguments, connects if disconnected, disconnects if connected."
}

do_pair() {
    echo "Removing device..."
    bluetoothctl remove "$MAC" 2>/dev/null
    echo "Scanning for device (put headphones in pairing mode)..."
    (
        bluetoothctl <<EOF
power on
agent on
pairable on
discoverable on
scan on
EOF
    ) &
    SCAN_PID=$!
    DEVICE_FOUND=0
    for _ in {1..30}; do
        if bluetoothctl devices 2>/dev/null | grep -q "$MAC"; then
            DEVICE_FOUND=1
            echo "Device found!"
            break
        fi
        sleep 1
    done
    kill $SCAN_PID 2>/dev/null
    wait $SCAN_PID 2>/dev/null
    bluetoothctl scan off 2>/dev/null
    if [ $DEVICE_FOUND -eq 0 ]; then
        echo "Device not found. Please ensure headphones are in pairing mode."
        exit 1
    fi
    echo "Pairing..."
    bluetoothctl pair "$MAC"
    bluetoothctl trust "$MAC"
    bluetoothctl connect "$MAC"
    echo "Pairing complete."
}

case "$1" in
    --pair)
        do_pair
        exit 0
        ;;
    --help)
        show_help
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

# Check current connection status
if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    echo "Disconnecting..."
    bluetoothctl disconnect "$MAC"
    STATUS="Disconnected"
else
    echo "Connecting..."
    OUTPUT=$(bluetoothctl connect "$MAC" 2>&1)
    echo "$OUTPUT"
    if echo "$OUTPUT" | grep -q "br-connection-key-missing"; then
        echo "Stale key detected (probably switched from another device). Re-pairing..."
        do_pair
    fi
    STATUS="Connected"
fi

# Get battery level
BATTERY=$(bluetoothctl info "$MAC" 2>/dev/null | grep "Battery Percentage" | grep -oP '\(\K[0-9]+(?=\))')

# Show status
if [ -n "$BATTERY" ]; then
    echo "$STATUS, battery at $BATTERY%"
else
    echo "$STATUS"
fi
