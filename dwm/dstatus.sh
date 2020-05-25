#!/bin/sh
while true; do
    xsetroot -name "$(date +%a-%d-%b-%R) BAT: $(acpi | grep "Battery 0" | awk '{print $4}' | sed s/,//)"
	sleep 1
done

