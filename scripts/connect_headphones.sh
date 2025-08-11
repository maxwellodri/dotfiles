#!/bin/bash
bluetoothctl power on
bluetoothctl agent on

MAC="5A:4D:2A:E8:7A:57"

if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
   bluetoothctl disconnect "$MAC"
else
   bluetoothctl connect "$MAC"
fi
