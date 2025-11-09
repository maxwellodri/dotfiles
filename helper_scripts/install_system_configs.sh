#!/bin/bash

# Enhanced System Configuration Installer with Service Management
# This script installs system configurations, udev rules, and systemd services
# with proper tracking and service management - runs as normal user with sudo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
# PURPLE='\033[0;35m'  # Uncomment if needed later
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Tracking arrays for changes
declare -a COPIED_FILES=()
declare -a UPDATED_FILES=()
declare -a SKIPPED_FILES=()
declare -a ERROR_FILES=()
declare -a ENABLED_SERVICES=()
declare -a STARTED_SERVICES=()
declare -a RESTARTED_SERVICES=()


# Function to find git root
find_git_root() {
    local current_dir
    current_dir="$(dirname "$(readlink -f "$0")")"
    while [ "$current_dir" != "/" ]; do
        if [ -d "$current_dir/.git" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    echo -e "${RED}Error: Not in a git repository${NC}" >&2
    return 1
}

# Check if user is in wheel group
check_wheel_membership() {
    if ! groups | grep -q '\bwheel\b'; then
        echo -e "${RED}Error: You must be a member of the 'wheel' group to run this script.${NC}"
        echo -e "${YELLOW}Current groups: $(groups)${NC}"
        exit 1
    fi
}

# Function to validate sudo access
validate_sudo() {
    echo -e "${CYAN}This script requires sudo access for system-level operations.${NC}"
    
    # Test sudo access
    if ! sudo -v; then
        echo -e "${RED}Error: Failed to obtain sudo privileges.${NC}"
        exit 1
    fi
    
    # Keep sudo alive during script execution
    (while true; do sudo -n true; sleep 50; done) &
    SUDO_KEEPALIVE_PID=$!
    
    # Ensure we kill the keepalive process on exit
    trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT
}

# Function to print section headers
print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# Function to extract service name from path
get_service_name() {
    basename "$1"
}

# Function to check if a systemd service file is valid
is_systemd_service() {
    local file="$1"
    [[ "$file" == *.service ]] || [[ "$file" == *.timer ]] || [[ "$file" == *.socket ]] || [[ "$file" == *.path ]]
}

# Function to manage system services (requires sudo)
manage_system_service() {
    local service_file="$1"
    local service_name
    service_name=$(get_service_name "$service_file")
    
    if ! is_systemd_service "$service_file"; then
        return 0
    fi
    
    echo -e "${CYAN}Managing system service: ${service_name}${NC}"
    
    # Check if service was already active
    local was_active=false
    if sudo systemctl is-active --quiet "$service_name"; then
        was_active=true
    fi
    
    # Enable the service
    if sudo systemctl enable "$service_name" 2>/dev/null; then
        ENABLED_SERVICES+=("$service_name")
        echo -e "  ${GREEN}✓ Enabled${NC}"
    fi
    
    # Start or restart the service
    if [ "$was_active" = true ]; then
        if sudo systemctl restart "$service_name" 2>/dev/null; then
            RESTARTED_SERVICES+=("$service_name")
            echo -e "  ${GREEN}✓ Restarted${NC}"
        else
            echo -e "  ${YELLOW}⚠ Failed to restart (may require reboot)${NC}"
        fi
    else
        if sudo systemctl start "$service_name" 2>/dev/null; then
            STARTED_SERVICES+=("$service_name")
            echo -e "  ${GREEN}✓ Started${NC}"
        else
            echo -e "  ${YELLOW}⚠ Failed to start (may require reboot)${NC}"
        fi
    fi
}

# Function to manage user services (no sudo needed)
manage_user_service() {
    local service_file="$1"
    local service_name
    service_name=$(get_service_name "$service_file")
    
    if ! is_systemd_service "$service_file"; then
        return 0
    fi
    
    echo -e "${CYAN}Managing user service: ${service_name}${NC}"
    
    # Check if service was already active
    local was_active=false
    if systemctl --user is-active --quiet "$service_name" 2>/dev/null; then
        was_active=true
    fi
    
    # Enable the service
    if systemctl --user enable "$service_name" 2>/dev/null; then
        ENABLED_SERVICES+=("user:$service_name")
        echo -e "  ${GREEN}✓ Enabled${NC}"
    fi
    
    # Start or restart the service
    if [ "$was_active" = true ]; then
        if systemctl --user restart "$service_name" 2>/dev/null; then
            RESTARTED_SERVICES+=("user:$service_name")
            echo -e "  ${GREEN}✓ Restarted${NC}"
        else
            echo -e "  ${YELLOW}⚠ Failed to restart (may require user session)${NC}"
        fi
    else
        if systemctl --user start "$service_name" 2>/dev/null; then
            STARTED_SERVICES+=("user:$service_name")
            echo -e "  ${GREEN}✓ Started${NC}"
        else
            echo -e "  ${YELLOW}⚠ Failed to start (may require user session)${NC}"
        fi
    fi
}

# Enhanced function to handle copying of files with tracking
copy_files() {
    local src="$1"
    local dst_dir="$2"
    dst_dir="${dst_dir%/}"
    local needs_sudo="${3:-false}"
    local is_user_service="${4:-false}"
    
    # Ensure the destination directory exists
    if [ "$needs_sudo" = "true" ]; then
        sudo mkdir -p "$dst_dir"
    else
        mkdir -p "$dst_dir"
    fi
    
    # Check if the source is a file
    if [ -f "$src" ]; then
        local filename
        filename=$(basename "$src")
        local dst="$dst_dir/$filename"
        
        # Check if the destination file exists
        local file_exists=false
        if [ "$needs_sudo" = "true" ]; then
            sudo test -e "$dst" && file_exists=true
        else
            test -e "$dst" && file_exists=true
        fi
        
        if [ "$file_exists" = true ]; then
            # If contents are the same, skip
            local files_identical=false
            if [ "$needs_sudo" = "true" ]; then
                sudo cmp -s "$src" "$dst" && files_identical=true
            else
                cmp -s "$src" "$dst" && files_identical=true
            fi
            
            if [ "$files_identical" = true ]; then
                echo -e "${YELLOW}↔ Skipping${NC} $filename ${YELLOW}(identical)${NC}"
                SKIPPED_FILES+=("$dst")
                return 0
            fi
            
            # Check if source is newer
            local src_is_newer=false
            if [ "$needs_sudo" = "true" ]; then
                # Get timestamps for comparison
                local src_time dst_time
                src_time=$(stat -c %Y "$src" 2>/dev/null)
                dst_time=$(sudo stat -c %Y "$dst" 2>/dev/null)
                [ "$src_time" -gt "$dst_time" ] && src_is_newer=true
            else
                [ "$src" -nt "$dst" ] && src_is_newer=true
            fi
            
            if [ "$src_is_newer" = true ]; then
                # Copy the file
                if [ "$needs_sudo" = "true" ]; then
                    sudo cp "$src" "$dst"
                    sudo chmod 644 "$dst"
                else
                    cp "$src" "$dst"
                    chmod 644 "$dst"
                fi
                echo -e "${GREEN}↻ Updated${NC} $filename"
                UPDATED_FILES+=("$dst")
                
                # Manage service if it's a systemd service file
                if [ "$is_user_service" = "true" ]; then
                    manage_user_service "$dst"
                elif [[ "$dst" == /etc/systemd/system/* ]]; then
                    manage_system_service "$dst"
                fi
            else
                # Get timestamps for error message
                local dst_date_modified src_date_modified
                if [ "$needs_sudo" = "true" ]; then
                    dst_date_modified=$(sudo stat -c "%Y-%m-%d %H:%M:%S" "$dst" 2>/dev/null)
                    src_date_modified=$(stat -c "%Y-%m-%d %H:%M:%S" "$src" 2>/dev/null)
                else
                    dst_date_modified=$(date -r "$dst" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
                    src_date_modified=$(date -r "$src" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
                fi
                echo -e "${RED}✗ Error${NC}: Destination file $dst is newer than source"
                echo -e "  ${RED}Dest: $dst_date_modified > Src: $src_date_modified${NC}"
                ERROR_FILES+=("$dst")
            fi
        else
            # Destination file does not exist, so copy source file
            if [ "$needs_sudo" = "true" ]; then
                sudo cp "$src" "$dst"
                sudo chmod 644 "$dst"
            else
                cp "$src" "$dst"
                chmod 644 "$dst"
            fi
            echo -e "${GREEN}+ Copied${NC} $filename ${GREEN}(new)${NC}"
            COPIED_FILES+=("$dst")
            
            # Manage service if it's a systemd service file
            if [ "$is_user_service" = "true" ]; then
                manage_user_service "$dst"
            elif [[ "$dst" == /etc/systemd/system/* ]]; then
                manage_system_service "$dst"
            fi
        fi
        return 0
    fi
    
    # If the source is a directory, iterate through the files
    if [ -d "$src" ]; then
        for file in "$src"/*; do
            [ -e "$file" ] || continue  # Skip if no files match
            copy_files "$file" "$dst_dir" "$needs_sudo" "$is_user_service"
        done
    fi
}

# Main script execution starts here

# Check if running as root - should run as normal user
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: This script should not be run as root.${NC}"
    echo -e "${YELLOW}Please run as a normal user who is a member of the wheel group.${NC}"
    exit 1
fi

# Check wheel group membership
check_wheel_membership

# Find git root
if ! GIT_ROOT=$(find_git_root); then
    exit 1
fi

echo -e "${CYAN}Git root found at: ${GIT_ROOT}${NC}"

# Change to git root
cd "$GIT_ROOT" || exit

# Check for dotfile tag
if [ ! -f "$GIT_ROOT/.dotfile_tag" ]; then
    echo -e "${RED}No $GIT_ROOT/.dotfile_tag found. Make sure to run installer_main.sh -> helper_scripts/makesymlinks.sh before this!${NC}"
    exit 1
fi

# Check if the required directories exist
if [ ! -d "udev-rules" ] || [ ! -d "systemd-services" ] || [ ! -d "system_configs" ]; then
    echo -e "${RED}Error: Required directories 'udev-rules', 'systemd-services', and 'system_configs' do not exist.${NC}"
    exit 1
fi


# Validate sudo access
validate_sudo

# Main installation process
print_header "Installing System Configuration Files"

# Copy dotfile tag (requires sudo)
echo -e "${CYAN}Copying $GIT_ROOT/.dotfile_tag to /etc/dotfile_tag${NC}"
sudo cp "$GIT_ROOT/.dotfile_tag" "/etc/dotfile_tag"

# Copy udev rules (requires sudo)
print_header "Installing udev Rules"
copy_files "udev-rules" "/etc/udev/rules.d" true

# Copy system systemd services (requires sudo)
print_header "Installing System Services"
copy_files "systemd-services/system" "/etc/systemd/system" true

# Copy user systemd services (no sudo needed)
print_header "Installing User Services"
USER_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$USER_CONFIG_HOME/systemd/user"
copy_files "systemd-services/user" "$USER_CONFIG_HOME/systemd/user" false

# Handle individual files in system_configs/etc
print_header "Installing System Configurations"
copy_files "system_configs/etc/tlp.conf" "/etc" true
copy_files "system_configs/etc/pacman.d/hooks" "/etc/pacman.d/hooks" true
copy_files "system_configs/etc/polkit-1/rules.d/" "/etc/polkit-1/rules.d" true
copy_files "system_configs/etc/systemd/" "/etc/systemd/" true

# Reload configurations
print_header "Reloading System Configurations"

echo -e "${CYAN}Setting systemd stop timeout to 15s...${NC}"
sudo mkdir -p /etc/systemd/system.conf.d && \
echo -e "[Manager]\nDefaultTimeoutStopSec=15s" | sudo tee /etc/systemd/system.conf.d/timeout.conf > /dev/null

echo -e "${CYAN}Reloading polkit...${NC}"
sudo systemctl reload polkit

echo -e "${CYAN}Reloading system daemon...${NC}"
sudo systemctl daemon-reload

echo -e "${CYAN}Reloading user daemon...${NC}"
systemctl --user daemon-reload

echo -e "${CYAN}Reloading udev rules...${NC}"
sudo udevadm control --reload-rules && sudo udevadm trigger

sudo systemctl enable atd
sudo systemctl start atd

# Print summary
print_header "Installation Summary"

echo -e "${BOLD}File Operations:${NC}"
echo -e "  ${GREEN}+ New files:${NC} ${#COPIED_FILES[@]}"
echo -e "  ${GREEN}↻ Updated files:${NC} ${#UPDATED_FILES[@]}"
echo -e "  ${YELLOW}↔ Skipped files:${NC} ${#SKIPPED_FILES[@]}"
echo -e "  ${RED}✗ Errors:${NC} ${#ERROR_FILES[@]}"

echo -e "\n${BOLD}Service Operations:${NC}"
echo -e "  ${GREEN}✓ Enabled services:${NC} ${#ENABLED_SERVICES[@]}"
echo -e "  ${GREEN}▶ Started services:${NC} ${#STARTED_SERVICES[@]}"
echo -e "  ${GREEN}↻ Restarted services:${NC} ${#RESTARTED_SERVICES[@]}"

# Show detailed lists if requested
if [ "${VERBOSE:-0}" -eq 1 ]; then
    if [ ${#COPIED_FILES[@]} -gt 0 ]; then
        echo -e "\n${BOLD}New files:${NC}"
        printf '%s\n' "${COPIED_FILES[@]}" | sed 's/^/  /'
    fi
    
    if [ ${#UPDATED_FILES[@]} -gt 0 ]; then
        echo -e "\n${BOLD}Updated files:${NC}"
        printf '%s\n' "${UPDATED_FILES[@]}" | sed 's/^/  /'
    fi
    
    if [ ${#ENABLED_SERVICES[@]} -gt 0 ]; then
        echo -e "\n${BOLD}Enabled services:${NC}"
        printf '%s\n' "${ENABLED_SERVICES[@]}" | sed 's/^/  /'
    fi
fi

# Final status
echo
if [ ${#ERROR_FILES[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ Configuration applied successfully!${NC}"
else
    echo -e "${YELLOW}${BOLD}⚠ Configuration applied with warnings. Check error messages above.${NC}"
fi

# Hint about verbose mode
if [ "${VERBOSE:-0}" -eq 0 ] && [ $((${#COPIED_FILES[@]} + ${#UPDATED_FILES[@]})) -gt 0 ]; then
    echo -e "\n${CYAN}Tip: Run with VERBOSE=1 to see detailed file lists${NC}"
fi

# Kill sudo keepalive process
kill $SUDO_KEEPALIVE_PID 2>/dev/null
