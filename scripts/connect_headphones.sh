#!/bin/bash
bluetoothctl power on >/dev/null 2>&1
bluetoothctl agent on >/dev/null 2>&1

MAC="5A:4D:2A:E8:7A:57"

if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
   BATTERY=$(bluetoothctl info "$MAC" | grep "Battery Percentage" | sed 's/.*(\([0-9]*\)).*/\1%/')
   bluetoothctl disconnect "$MAC" >/dev/null 2>&1
   STATUS="Disconnected"
else
   bluetoothctl connect "$MAC" >/dev/null 2>&1
   sleep 1
   BATTERY=$(bluetoothctl info "$MAC" | grep "Battery Percentage" | sed 's/.*(\([0-9]*\)).*/\1%/')
   STATUS="Connected"
fi

# Show status and battery
if [ -n "$BATTERY" ]; then
   echo "$STATUS, battery at $BATTERY"
else
   echo "$STATUS"
fi
