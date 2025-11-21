#!/bin/bash

MAC="5A:4D:2A:E8:7A:57"

# Initialize bluetooth
bluetoothctl power on >/dev/null 2>&1
bluetoothctl agent on >/dev/null 2>&1

# Handle --pair flag
if [ "$1" = "--pair" ]; then
    bluetoothctl pairable on >/dev/null 2>&1
    bluetoothctl discoverable on >/dev/null 2>&1
    echo "Removing device..."
    bluetoothctl remove "$MAC" 2>/dev/null
    echo "Scanning for device (put headphones in pairing mode)..."
    bluetoothctl scan on >/dev/null 2>&1 &
    SCAN_PID=$!
    
    # Wait for device to appear
    for i in {1..30}; do
        if bluetoothctl devices | grep -q "$MAC"; then
            break
        fi
        sleep 1
    done
    
    kill $SCAN_PID 2>/dev/null
    bluetoothctl scan off >/dev/null 2>&1
    
    echo "Pairing..."
    bluetoothctl pair "$MAC"
    bluetoothctl trust "$MAC"
    bluetoothctl connect "$MAC"
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
