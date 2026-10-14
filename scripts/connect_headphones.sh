#!/usr/bin/env bash
MAC="8F:5A:78:16:18:40"

# Initialize bluetooth
bluetoothctl power on >/dev/null 2>&1

if bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; then
    echo "Disconnecting..."
    bluetoothctl disconnect "$MAC"
    STATUS="Disconnected"
else
    if ! bluetoothctl info "$MAC" 2>/dev/null | grep -q "Paired: yes"; then
        echo "Not paired (put headphones in pairing mode)..."
        bluetoothctl pair "$MAC"
        bluetoothctl trust "$MAC"
    fi
    echo "Connecting..."
    bluetoothctl connect "$MAC"
    STATUS="Connected"
fi

BATTERY=$(bluetoothctl info "$MAC" 2>/dev/null | grep "Battery Percentage" | grep -oP '\(\K[0-9]+(?=\))')

if [ -n "$BATTERY" ]; then
    echo "$STATUS, battery at $BATTERY%"
else
    echo "$STATUS"
fi
