#!/bin/bash

# Validation script for RX 6900 XT stability fixes
# Reports failures only, copies to clipboard

FAILURES=()

echo "RX 6900 XT Stability Validation"
echo "================================"
echo ""

# Check kernel parameters
echo "Checking kernel parameters..."
CURRENT_PARAMS=$(cat /proc/cmdline)
EXPECTED_PARAMS="amd_iommu=off amdgpu.runpm=0 amdgpu.ppfeaturemask=0xfffd7fff"

echo "Current kernel parameters:"
echo "  $CURRENT_PARAMS"
echo ""

for param in $EXPECTED_PARAMS; do
    if ! echo "$CURRENT_PARAMS" | grep -q "$param"; then
        FAILURES+=("FAIL: Kernel parameter '$param' not found in /proc/cmdline")
    fi
done

# Check for common typos
if echo "$CURRENT_PARAMS" | grep -q "amd_iommu=of"; then
    FAILURES+=("FAIL: Typo detected - 'amd_iommu=of' should be 'amd_iommu=off'")
fi

# Check IOMMU is disabled
echo "Checking IOMMU status..."
if journalctl -b -k --no-pager | grep -iq "amd-vi.*enabled"; then
    FAILURES+=("FAIL: IOMMU is enabled (should be disabled)")
fi

if journalctl -b -k --no-pager | grep -iq "iommu.*Event logged.*INVALID_DEVICE_REQUEST"; then
    FAILURES+=("FAIL: IOMMU errors detected in logs")
fi

# Check AMD PState is not loaded
echo "Checking AMD PState status..."
if lsmod | grep -q "^amd_pstate "; then
    FAILURES+=("FAIL: amd_pstate module is loaded (should be disabled)")
fi

if ! lsmod | grep -q "^acpi_cpufreq "; then
    FAILURES+=("FAIL: acpi_cpufreq module not loaded (CPU freq control issue)")
fi

# Check AMDGPU driver
echo "Checking AMDGPU driver..."
if ! lsmod | grep -q "^amdgpu "; then
    FAILURES+=("FAIL: amdgpu driver not loaded")
fi

# Check GPU frequency control
if [ ! -f /sys/class/drm/card1/device/gpu_busy_percent ]; then
    FAILURES+=("FAIL: GPU frequency controls not available")
fi

# Check system time stability
echo "Checking system time stability..."
if journalctl -b --no-pager | grep -q "Time jumped backwards"; then
    FAILURES+=("FAIL: System time instability detected")
fi

# Check for recent IOMMU errors
echo "Checking for IOMMU errors..."
if journalctl -b -k --no-pager | grep -q "AMD-Vi.*Event logged.*INVALID_DEVICE_REQUEST"; then
    FAILURES+=("FAIL: IOMMU device errors detected in current boot")
fi

# Check for hardware errors (excluding normal MCE initialization)
echo "Checking for hardware errors..."
if journalctl -b -k --no-pager | grep -qi "mce.*error\|hardware error" | grep -v "MCE: In-kernel MCE decoding enabled"; then
    FAILURES+=("FAIL: Hardware errors detected in logs")
fi

# Check for critical errors
echo "Checking for critical errors..."
if journalctl -b -p crit --no-pager | grep -q .; then
    FAILURES+=("FAIL: Critical errors detected in current boot")
fi

# Check CPU frequency sanity
echo "Checking CPU frequency..."
CPU_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
if [ -n "$CPU_FREQ" ]; then
    if [ "$CPU_FREQ" -gt 5000000 ]; then
        FAILURES+=("FAIL: Impossible CPU frequency detected: $CPU_FREQ kHz")
    fi
else
    FAILURES+=("FAIL: CPU frequency control not working")
fi

# Check system uptime
echo "Checking system uptime..."
UPTIME=$(uptime | awk '{print $3}')
if [ "$UPTIME" -lt 5 ]; then
    FAILURES+=("WARN: System uptime less than 5 minutes - may be unstable")
fi

# Check GPU temperature
if [ -f /sys/class/drm/card1/device/hwmon/hwmon1/temp1_input ]; then
    GPU_TEMP=$(cat /sys/class/drm/card1/device/hwmon/hwmon1/temp1_input 2>/dev/null)
    GPU_TEMP_C=$((GPU_TEMP / 1000))
    if [ "$GPU_TEMP_C" -gt 90 ]; then
        FAILURES+=("WARN: High GPU temperature: ${GPU_TEMP_C}°C")
    fi
fi

# Output results
echo ""
echo "================================"
echo "VALIDATION RESULTS"
echo "================================"
echo ""

if [ ${#FAILURES[@]} -eq 0 ]; then
    echo "✓ ALL CHECKS PASSED"
    echo ""
    echo "System is stable. Ready for manual testing."
    echo ""
    echo "Recommended testing sequence:"
    echo "1. Sleep/wake test (5-10 minutes)"
    echo "2. Light gaming test (15-20 minutes)"
    echo "3. GPU-heavy game test (30-45 minutes)"
    echo "4. Monitor for 24-48 hours"
    OUTPUT="✓ ALL CHECKS PASSED - System is stable and ready for manual testing."
else
    echo "✗ FAILURES DETECTED:"
    echo ""
    for failure in "${FAILURES[@]}"; do
        echo "  - $failure"
    done
    echo ""

    # Check for specific fixable issues
    if echo "$CURRENT_PARAMS" | grep -q "amd_iommu=of"; then
        echo "QUICK FIX:"
        echo "  1. Edit /etc/default/grub"
        echo "  2. Change 'amd_iommu=of' to 'amd_iommu=off'"
        echo "  3. Run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
        echo "  4. Reboot and re-run validation"
        echo ""
    fi

    echo "Please address failures before proceeding with testing."
    OUTPUT="✗ VALIDATION FAILED - Issues detected:\n\n"
    for failure in "${FAILURES[@]}"; do
        OUTPUT+="- $failure\n"
    done
fi

echo ""
echo "================================"

# Copy to clipboard
if command -v xclip &> /dev/null; then
    echo -e "$OUTPUT" | xclip -selection clipboard
    echo "✓ Results copied to clipboard"
elif command -v xsel &> /dev/null; then
    echo -e "$OUTPUT" | xsel --clipboard
    echo "✓ Results copied to clipboard"
else
    echo "✗ Clipboard tools not found (xclip/xsel)"
fi

# Exit with appropriate code
if [ ${#FAILURES[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi