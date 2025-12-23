#!/bin/bash

MAC="5A:4D:2A:E8:7A:57"

# Initialize bluetooth
bluetoothctl power on >/dev/null 2>&1
bluetoothctl agent on >/dev/null 2>&1

# Handle --pair flag
if [ "$1" = "--pair" ]; then
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
    for i in {1..30}; do
        if bluetoothctl devices 2>/dev/null | grep -q "$MAC"; then
            DEVICE_FOUND=1
            echo "Device found!"
            break
        fi
        sleep 1
    done

    kill $SCAN_PID 2>/dev/null
    wait $SCAN_PID 2>/dev/null

    if [ $DEVICE_FOUND -eq 0 ]; then
        echo "Device not found. Please ensure headphones are in pairing mode."
        exit 1
    fi

    echo "Pairing..."
    bluetoothctl pair "$MAC"
    bluetoothctl trust "$MAC"
    bluetoothctl connect "$MAC"

    echo "Pairing complete."
    exit 0
fi

# Check current connection status
if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    echo "Disconnecting..."
    bluetoothctl disconnect "$MAC"
    STATUS="Disconnected"
else
    echo "Connecting..."
    bluetoothctl connect "$MAC"
    STATUS="Connected"
fi

# Get battery level
BATTERY=$(bluetoothctl info "$MAC" 2>/dev/null | grep "Battery Percentage" | awk '{print $4}' | tr -d '()')

# Show status
if [ -n "$BATTERY" ]; then
    echo "$STATUS, battery at $BATTERY%"
else
    echo "$STATUS"
fi
