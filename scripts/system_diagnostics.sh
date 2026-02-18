#!/bin/bash

# System Diagnostic Script for RX 6900 XT crash investigation
# Gathers logs and system info, copies to X11 clipboard

OUTPUT_FILE="/tmp/system_diagnostics_$(date +%Y%m%d_%H%M%S).txt"

echo "=========================================" | tee "$OUTPUT_FILE"
echo "SYSTEM DIAGNOSTIC REPORT" | tee -a "$OUTPUT_FILE"
echo "Generated: $(date)" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "SYSTEM INFORMATION" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Kernel Version ---"
    uname -r
    uname -m
    echo ""

    echo "--- OS Release ---"
    cat /etc/os-release | grep -E "^(NAME|VERSION|ID)=
" | head -3
    echo ""

    echo "--- System Uptime ---"
    uptime
    echo ""

    echo "--- Last Boot Time ---"
    who -b
    echo ""

    echo "--- Recent Boot History ---"
    sudo journalctl --list-boots | head -15
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "HARDWARE INFORMATION" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- CPU Information ---"
    grep -m 1 "model name" /proc/cpuinfo
    echo "CPU Cores: $(nproc)"
    echo ""

    echo "--- GPU Information ---"
    lspci | grep -i "vga\|display"
    echo ""

    echo "--- Memory Information ---"
    free -h
    echo ""

    echo "--- Motherboard/Chipset ---"
    sudo dmidecode -s baseboard-product-name 2>/dev/null || echo "DMIDECODE unavailable"
    sudo dmidecode -s baseboard-manufacturer 2>/dev/null
    echo ""

    echo "--- PCIe Devices ---"
    lspci -nn | grep -E "(VGA|Display|3D|PCIe bridge)"
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "GPU DRIVER INFORMATION" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- AMDGPU Driver Status ---"
    lsmod | grep amdgpu
    echo ""

    echo "--- GPU Device Files ---"
    find /sys/class/drm/card*/device/ -maxdepth 1 -type l 2>/dev/null | head -20
    echo ""

    echo "--- GPU Frequency/Usage (if available) ---"
    for dir in /sys/class/drm/card*/device/; do
        if [ -f "${dir}gpu_busy_percent" ]; then
            echo "Card: ${dir}"
            cat "${dir}gpu_busy_percent" 2>/dev/null && echo "% GPU busy"
            cat "${dir}mem_busy_percent" 2>/dev/null && echo "% VRAM busy"
            cat "${dir}gpu_clock" 2>/dev/null && echo "MHz GPU clock"
            cat "${dir}mem_clock" 2>/dev/null && echo "MHz VRAM clock"
            echo ""
        fi
    done
    echo ""

    echo "--- GPU Temperature (if available) ---"
    for hwmon in /sys/class/drm/card*/device/hwmon/hwmon*; do
        if [ -f "${hwmon}/temp1_input" ]; then
            temp=$(cat "${hwmon}/temp1_input")
            echo "GPU Temperature: $((temp/1000))°C"
            break
        fi
    done
    echo ""

    echo "--- Loaded AMDGPU Firmware ---"
    dmesg | grep -i "amdgpu" | grep -i "firmware" | head -10
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "CURRENT TEMPERATURES" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    if command -v sensors &> /dev/null; then
        sensors
    else
        echo "lm-sensors not installed"
    fi
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "KERNEL MESSAGES (CURRENT BOOT)" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Last 50 lines ---"
    dmesg | tail -50
    echo ""

    echo "--- AMDGPU/GPU errors ---"
    dmesg | grep -i "amdgpu\|gpu\|drm.*error" | tail -20
    echo ""

    echo "--- PCIe/IOMMU errors ---"
    dmesg | grep -i "pcie\|iommu\|aer\|amd-vi" | tail -20
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "KERNEL MESSAGES (PREVIOUS BOOT)" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Last 50 lines ---"
    sudo journalctl -k -b -1 --no-pager | tail -50
    echo ""

    echo "--- AMDGPU/GPU errors ---"
    sudo journalctl -k -b -1 --no-pager | grep -i "amdgpu\|gpu\|drm.*error" | tail -20
    echo ""

    echo "--- PCIe/IOMMU errors ---"
    sudo journalctl -k -b -1 --no-pager | grep -i "pcie\|iommu\|aer\|amd-vi" | tail -20
    echo ""

    echo "--- Machine Check Exceptions (Hardware Errors) ---"
    sudo journalctl -k -b -1 --no-pager | grep -i "mce\|machine check\|hardware error" | tail -20
    echo ""

    echo "--- Thermal warnings ---"
    sudo journalctl -k -b -1 --no-pager | grep -i "thermal\|temperature\|overheat" | tail -20
    echo ""

    echo "--- Critical/Emergency errors ---"
    sudo journalctl -b -1 -p crit..emerg --no-pager | tail -20
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "SYSTEMD LOGS - RECENT ERRORS" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Last 100 error/warning lines ---"
    sudo journalctl -b -p err..warn --no-pager | tail -100
    echo ""

    echo "--- Segmentation faults ---"
    sudo journalctl -b --no-pager | grep -i "segfault" | tail -20
    echo ""

    echo "--- Kernel panics/oops ---"
    sudo journalctl -b --no-pager | grep -i "panic\|oops" | tail -20
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "SLEEP/WAKE INFORMATION" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Recent suspend/resume events ---"
    sudo journalctl -b --no-pager | grep -i "suspend\|resume\|sleep\|wake" | tail -30
    echo ""

    echo "--- Time jumps (system instability indicator) ---"
    sudo journalctl -b --no-pager | grep -i "time jumped\|time.*backwards" | tail -10
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "POWER MANAGEMENT" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- AMD PState errors (from logs) ---"
    sudo journalctl -k -b --no-pager | grep -i "amd_pstate" | tail -10
    echo ""

    echo "--- CPU frequency scaling ---"
    if [ -f /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq ]; then
        echo "CPU 0 current: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq) MHz"
        echo "CPU 0 max: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq) MHz"
    fi
    echo ""

    echo "--- Power supply (if detectable) ---"
    ls /sys/class/power_supply/ 2>/dev/null
    for psu in /sys/class/power_supply/*; do
        if [ -f "$psu/type" ]; then
            type=$(cat "$psu/type")
            if [ -f "$psu/capacity" ]; then
                echo "$psu ($type): $(cat $psu/capacity)%"
            fi
        fi
    done
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "GRAPHICS/GL INFORMATION" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    if command -v glxinfo &> /dev/null; then
        echo "--- OpenGL Information ---"
        glxinfo | grep -E "OpenGL version|OpenGL renderer|OpenGL vendor" | head -5
    else
        echo "glxinfo not installed"
    fi
    echo ""

    if command -v vulkaninfo &> /dev/null; then
        echo "--- Vulkan Information ---"
        vulkaninfo 2>/dev/null | grep -E "deviceName|driverVersion|apiVersion" | head -10
    else
        echo "vulkaninfo not installed"
    fi
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "INSTALLED PACKAGES (GPU RELATED)" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Graphics packages ---"
    pacman -Qs mesa xf86-video-amdgpu vulkan 2>/dev/null | grep -E "^(local|  )" | head -20
    echo ""

    echo "--- Linux kernel packages ---"
    pacman -Qs "^linux" | grep -E "^(local|  )" | head -10
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "RECENT CORE DUMPS" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"

{
    echo "--- Core dump locations ---"
    find /var/lib/systemd/coredump -maxdepth 1 -type f -exec ls -lh {} \; 2>/dev/null | head -20
    echo ""

    echo "--- Recent coredump events ---"
    sudo journalctl -b --no-pager | grep -i "coredump\|Process.*dumped core" | tail -10
    echo ""

} | tee -a "$OUTPUT_FILE"

echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "END OF DIAGNOSTIC REPORT" | tee -a "$OUTPUT_FILE"
echo "=========================================" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Copy to clipboard
echo "Copying diagnostic output to clipboard..."

if command -v xclip &> /dev/null; then
    xclip -selection clipboard -i "$OUTPUT_FILE"
    echo "✓ Successfully copied to clipboard using xclip"
elif command -v xsel &> /dev/null; then
    xsel --clipboard < "$OUTPUT_FILE"
    echo "✓ Successfully copied to clipboard using xsel"
else
    echo "✗ Neither xclip nor xsel found. Install one of them for clipboard support."
    echo "  sudo pacman -S xclip   # or xsel"
fi

echo ""
echo "Report also saved to: $OUTPUT_FILE"
echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"