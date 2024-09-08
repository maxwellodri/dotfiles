#!/bin/env python3
import subprocess
import math

def get_battery_info():
    try:
        # Run the acpi command and capture its output
        output = subprocess.check_output(['acpi'], encoding='utf-8').strip().split('\n')
        
        total_percentage = 0
        battery_count = 0
        charging = False
        discharging = False
        fully_charged = True
        
        for line in output:
            parts = line.split(', ')
            if len(parts) >= 2:
                status = parts[0].split(': ')[1]
                percentage = int(parts[1].replace('%', ''))
                total_percentage += percentage
                battery_count += 1
                
                # Update battery status flags
                if "Discharging" in status:
                    discharging = True
                    fully_charged = False
                elif "Charging" in status:
                    charging = True
                    fully_charged = False
                elif "Full" in status:
                    fully_charged = fully_charged and True  # Keep fully charged if all are full
        
        # Calculate average battery percentage
        average_percentage = total_percentage / battery_count if battery_count > 0 else 0
        average_percentage = math.ceil(average_percentage)
        
        # Determine overall battery state
        if fully_charged:
            battery_state = "Fully Charged"
        elif charging:
            battery_state = "Charging"
        else:
            battery_state = "Discharging"
        
        return average_percentage, battery_state, discharging

    except subprocess.CalledProcessError:
        return "Error retrieving battery information"

def get_battery_emoji(state, percentage, discharging):
    if discharging and percentage < 20:
        return "❗🚨 "
    return {
        "Fully Charged": "🔋🤪",
        "Charging": "🔋👍",
        "Discharging": "🔋👎"
    }.get(state, "❓")

# Get the battery information
average_percentage, battery_state, discharging = get_battery_info()

# Get the corresponding emoji for the state
battery_emoji = get_battery_emoji(battery_state, average_percentage, discharging)

# Output in desired format with emoji and percentage
print(f"{battery_emoji}: {average_percentage}%")
