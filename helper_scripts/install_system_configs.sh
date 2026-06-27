#!/bin/bash

. "$(cd "$(dirname "$(readlink -f "$0")")" && git rev-parse --show-toplevel)/.config/sh/shutil.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

declare -a COPIED_FILES=()
declare -a UPDATED_FILES=()
declare -a SKIPPED_FILES=()
declare -a ERROR_FILES=()
declare -a ENABLED_SERVICES=()
declare -a STARTED_SERVICES=()


log_verbose() {
    [ "${VERBOSE:-0}" -eq 1 ] && echo -e "$@"
}

print_header() {
    [ "${VERBOSE:-0}" -eq 1 ] && echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

enable_service() {
    local user_mode=false
    if [ "$1" = "--user" ]; then
        user_mode=true
        shift
    fi
    local svc="$1"
    if [ "$user_mode" = true ]; then
        if systemctl --user enable "$svc" 2>/dev/null; then
            ENABLED_SERVICES+=("user:$svc")
            echo -e "  ${GREEN}✓ enabled${NC} user:$svc"
        fi
        if systemctl --user start "$svc" 2>/dev/null; then
            STARTED_SERVICES+=("user:$svc")
        else
            echo -e "  ${YELLOW}⚠ user:$svc did not start (may need a session)${NC}"
        fi
    else
        if run_elevated systemctl enable "$svc" 2>/dev/null; then
            ENABLED_SERVICES+=("$svc")
            echo -e "  ${GREEN}✓ enabled${NC} $svc"
        fi
        if run_elevated systemctl start "$svc" 2>/dev/null; then
            STARTED_SERVICES+=("$svc")
        else
            echo -e "  ${YELLOW}⚠ $svc did not start${NC}"
        fi
    fi
}

copy_host_files() {
    local tag="$1"
    shift
    copy_files "system_configs/host-specific/$tag/$1" "${@:2}"
}

# Enhanced function to handle copying of files with tracking
copy_files() {
    local src="$1"
    local dst_dir="$2"
    dst_dir="${dst_dir%/}"
    local needs_sudo="${3:-false}"
    local is_user_service="${4:-false}"
    local file_perms="${5:-644}"
    local file_group="${6:-}"

    # Ensure the destination directory exists
    if [ "$needs_sudo" = "true" ]; then
        run_elevated mkdir -p "$dst_dir"
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
            run_elevated test -e "$dst" && file_exists=true
        else
            test -e "$dst" && file_exists=true
        fi

        if [ "$file_exists" = true ]; then
            # If contents are the same, skip
            local files_identical=false
            if [ "$needs_sudo" = "true" ]; then
                run_elevated cmp -s "$src" "$dst" && files_identical=true
            else
                cmp -s "$src" "$dst" && files_identical=true
            fi

            if [ "$files_identical" = true ]; then
                local current_mode current_group needs_perm_update=false
                if [ "$needs_sudo" = "true" ]; then
                    current_mode=$(run_elevated stat -c '%a' "$dst")
                    current_group=$(run_elevated stat -c '%G' "$dst")
                else
                    current_mode=$(stat -c '%a' "$dst")
                    current_group=$(stat -c '%G' "$dst")
                fi
                if [ "$current_mode" != "$file_perms" ] || { [[ -n "$file_group" ]] && [ "$current_group" != "$file_group" ]; }; then
                    needs_perm_update=true
                fi

                if [ "$needs_perm_update" = false ]; then
                    echo -e "${YELLOW}↔ Skipping${NC} $dst ${YELLOW}(identical)${NC}"
                    SKIPPED_FILES+=("$dst")
                    return 0
                fi

                if [ "$needs_sudo" = "true" ]; then
                    run_elevated chmod "$file_perms" "$dst"
                    [[ -n "$file_group" ]] && run_elevated chgrp "$file_group" "$dst"
                else
                    chmod "$file_perms" "$dst"
                    [[ -n "$file_group" ]] && chgrp "$file_group" "$dst"
                fi
                echo -e "${GREEN}↻ Updated${NC} $dst ${GREEN}(permissions)${NC}"
                UPDATED_FILES+=("$dst")
                return 0
            fi

            # Check if source is newer
            local src_is_newer=false
            if [ "$needs_sudo" = "true" ]; then
                # Get timestamps for comparison
                local src_time dst_time
                src_time=$(stat -c %Y "$src" 2>/dev/null)
                dst_time=$(run_elevated stat -c %Y "$dst" 2>/dev/null)
                [ "$src_time" -gt "$dst_time" ] && src_is_newer=true
            else
                [ "$src" -nt "$dst" ] && src_is_newer=true
            fi

            if [ "$src_is_newer" = true ]; then
                # Copy the file
                if [ "$needs_sudo" = "true" ]; then
                    run_elevated cp "$src" "$dst"
                    run_elevated chmod "$file_perms" "$dst"
                    [[ -n "$file_group" ]] && run_elevated chgrp "$file_group" "$dst"
                else
                    cp "$src" "$dst"
                    chmod "$file_perms" "$dst"
                    [[ -n "$file_group" ]] && chgrp "$file_group" "$dst"
                fi
                echo -e "${GREEN}↻ Updated${NC} $dst"
                UPDATED_FILES+=("$dst")
            else
                # Get timestamps for error message
                local dst_date_modified src_date_modified
                if [ "$needs_sudo" = "true" ]; then
                    dst_date_modified=$(run_elevated stat -c "%Y-%m-%d %H:%M:%S" "$dst" 2>/dev/null)
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
                run_elevated cp "$src" "$dst"
                run_elevated chmod "$file_perms" "$dst"
                [[ -n "$file_group" ]] && run_elevated chgrp "$file_group" "$dst"
            else
                cp "$src" "$dst"
                chmod "$file_perms" "$dst"
                [[ -n "$file_group" ]] && chgrp "$file_group" "$dst"
            fi
            echo -e "${GREEN}+ Copied${NC} $dst ${GREEN}(new)${NC}"
            COPIED_FILES+=("$dst")
        fi
        return 0
    fi

    # If the source is a directory, iterate through the files
    if [ -d "$src" ]; then
        for file in "$src"/*; do
            [ -e "$file" ] || continue  # Skip if no files match
            if [ -d "$file" ]; then
                copy_files "$file" "$dst_dir/$(basename "$file")" "$needs_sudo" "$is_user_service" "$file_perms" "$file_group"
            else
                copy_files "$file" "$dst_dir" "$needs_sudo" "$is_user_service" "$file_perms" "$file_group"
            fi
        done
    fi
}

# Main script execution starts here

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: This script should not be run as root.${NC}"
    echo -e "${YELLOW}Please run as a normal user who is a member of the wheel group.${NC}"
    exit 1
fi

GIT_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && git rev-parse --show-toplevel)"

log_verbose "${CYAN}Git root found at: ${GIT_ROOT}${NC}"

cd "$GIT_ROOT" || exit

if [ ! -f "$GIT_ROOT/.dotfile_tag" ]; then
    echo -e "${RED}No $GIT_ROOT/.dotfile_tag found. Make sure to run installer_main.sh -> helper_scripts/makesymlinks.sh before this!${NC}"
    exit 1
fi

dotfile_tag="$(cat "$GIT_ROOT/.dotfile_tag")"

if [ ! -d "systemd-services" ] && [ ! -d "system_configs" ]; then
    echo -e "${RED}Error: Required directories 'systemd-services' and 'system_configs' do not exist.${NC}"
    exit 1
fi

run_elevated_init || exit 1

# Main installation process
print_header "Installing System Configuration Files"

# Copy dotfile tag (requires elevation)
log_verbose "${CYAN}Copying $GIT_ROOT/.dotfile_tag to /etc/dotfile_tag${NC}"
run_elevated cp "$GIT_ROOT/.dotfile_tag" "/etc/dotfile_tag"
run_elevated chmod 664 "/etc/dotfile_tag"
run_elevated chgrp wheel "/etc/dotfile_tag"

# Copy system systemd services (requires elevation)
print_header "Installing System Services"
copy_files "systemd-services/system" "/etc/systemd/system" true false "644" "root"

# Copy user systemd services (no elevation needed)
print_header "Installing User Services"
USER_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$USER_CONFIG_HOME/systemd/user"
copy_files "systemd-services/user" "$USER_CONFIG_HOME/systemd/user" false

# Handle individual files in system_configs/etc
print_header "Installing System Configurations"
copy_files "system_configs/etc/NetworkManager" "/etc/NetworkManager" true false "644" "root"
copy_files "system_configs/etc/tlp.conf" "/etc" true false "644" "root"
copy_files "system_configs/etc/pacman.d/hooks" "/etc/pacman.d/hooks" true false "644" "root"
copy_files "system_configs/etc/polkit-1/rules.d/" "/etc/polkit-1/rules.d" true false "644" "root"
copy_files "system_configs/usr/share/xdg-desktop-portal" "/usr/share/xdg-desktop-portal" true false "644" "root"
    copy_files "system_configs/etc/sudoers.d" "/etc/sudoers.d" true false "440" "root"
    if [ "$dotfile_tag" = "pc" ]; then
        #copy_files "system_configs/etc/systemd/zram-generator.conf" "/etc/systemd/zram-generator.conf" true
        copy_files "system_configs/etc/systemd/" "/etc/systemd/" true false "644" "root"
    fi

    # Host-specific configurations
    copy_host_files "$dotfile_tag" "etc/wireguard/wg0.conf" "/etc/wireguard" true false "600" "root"

# Reload configurations
print_header "Reloading System Configurations"

log_verbose "${CYAN}Setting systemd stop timeout to 15s...${NC}"
run_elevated mkdir -p /etc/systemd/system.conf.d && \
echo -e "[Manager]\nDefaultTimeoutStopSec=15s" | run_elevated tee /etc/systemd/system.conf.d/timeout.conf > /dev/null

log_verbose "${CYAN}Reloading polkit...${NC}"
run_elevated systemctl reload polkit

log_verbose "${CYAN}Reloading system daemon...${NC}"
run_elevated systemctl daemon-reload

log_verbose "${CYAN}Reloading user daemon...${NC}"
systemctl --user daemon-reload

log_verbose "${CYAN}Enabling linger for user ${USER}...${NC}"
run_elevated loginctl enable-linger "$USER"

log_verbose "${CYAN}Reloading udev rules...${NC}"
run_elevated udevadm control --reload-rules && run_elevated udevadm trigger

print_header "Enabling Services"

enable_service git-reminder.timer
enable_service check_for_docker_updates.timer

enable_service --user git-reminder.timer
enable_service --user dunst.service

[ "$dotfile_tag" = "pc" ] && enable_service --user vps-socks.service

enable_service atd

if [ "${VERBOSE:-0}" -eq 1 ]; then
    print_header "Installation Summary"

    echo -e "${BOLD}File Operations:${NC}"
    echo -e "  ${GREEN}+ New files:${NC} ${#COPIED_FILES[@]}"
    echo -e "  ${GREEN}↻ Updated files:${NC} ${#UPDATED_FILES[@]}"
    echo -e "  ${YELLOW}↔ Skipped files:${NC} ${#SKIPPED_FILES[@]}"
    echo -e "  ${RED}✗ Errors:${NC} ${#ERROR_FILES[@]}"

    echo -e "\n${BOLD}Service Operations:${NC}"
    echo -e "  ${GREEN}✓ Enabled services:${NC} ${#ENABLED_SERVICES[@]}"
    echo -e "  ${GREEN}▶ Started services:${NC} ${#STARTED_SERVICES[@]}"

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
    echo -e "${GREEN}${BOLD}✓ System Configuration applied successfully!${NC}"
else
    echo -e "${YELLOW}${BOLD}⚠ System Configuration applied with warnings. Check error messages above.${NC}"
fi

run_elevated_cleanup
