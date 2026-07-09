#!/bin/bash
#
# install_system_configs.sh — install system-wide config (systemd units, /etc
# files, polkit/portal rules, …) that can't be symlinked from the dotfiles
# repo because the destinations are root-owned or live outside $HOME.
#
# Usage: bash helper_scripts/install_system_configs.sh
#   - run as a normal (wheel) user; elevation goes through shutil.sh's
#     run_elevated (sudo). Never run as root.
#   - requires .dotfile_tag (created by makesymlinks.sh) at the repo root.
#   - VERBOSE=1 adds section headers and the detailed file/service lists.
#
# Called from install.sh. Sources are copied (not symlinked) so local edits to
# the destinations are protected: identical files are skipped, a newer source
# updates, and a NEWER destination is an error (never silently clobbered).
#
. "$(cd "$(dirname "$(readlink -f "$0")")" && git rev-parse --show-toplevel)/.config/sh/shutil.sh"

set -o pipefail

# --- reporting ---------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

COPIED_FILES=(); UPDATED_FILES=(); SKIPPED_FILES=(); ERROR_FILES=()
ENABLED_SERVICES=(); STARTED_SERVICES=()

log_verbose() { [ "${VERBOSE:-0}" -eq 1 ] && echo -e "$1"; }
header()      { [ "${VERBOSE:-0}" -eq 1 ] && echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"; }

# --- services ----------------------------------------------------------------
# enable_service [--user] <unit> : enable + start a unit, recording outcomes.
# Warns (instead of silently no-op'ing) if enable fails.
enable_service() {
    local scope="" elev=run_elevated
    # user units need no elevation; system units go through sudo so they reuse
    # the credential cached by run_elevated_init (no second polkit/GUI prompt).
    [ "$1" = "--user" ] && { scope="--user"; elev=""; shift; }
    local svc label
    svc="$1"
    label="${scope:+user:}$svc"

    if $elev systemctl $scope enable "$svc" 2>/dev/null; then
        ENABLED_SERVICES+=("$label")
        echo -e "  ${GREEN}✓ enabled${NC} $label"
    else
        echo -e "  ${RED}✗ failed to enable${NC} $label ${RED}(unit missing?)${NC}"
        return 1
    fi
    if $elev systemctl $scope start "$svc" 2>/dev/null; then
        STARTED_SERVICES+=("$label")
    else
        echo -e "  ${YELLOW}⚠ did not start${NC} $label ${YELLOW}(may need a session)${NC}"
    fi
}

# --- file copy ---------------------------------------------------------------
# apply_perms <as_root> <path> <mode> [group]: chmod (+ optional chgrp), routed
# through `as_root` (empty = unsudo'd) so copy_files' branches stay DRY.
apply_perms() {
    local as_root="$1" path="$2" mode="$3" group="${4:-}"
    $as_root chmod "$mode" "$path"
    [ -n "$group" ] && $as_root chgrp "$group" "$path"
}

# copy_files <src> <dst_dir> [needs_sudo] [mode] [group]
#   src may be a file or a directory (recursed into). Each destination is
#   recorded in the REPORT arrays. needs_sudo routes every fs op through
#   run_elevated via the `as_root` prefix (empty => run unsudo'd), which is what
#   collapses the old duplicated sudo/non-sudo branches.
copy_files() {
    local src="$1" dst_dir="${2%/}" needs_sudo="${3:-false}"
    local mode="${4:-644}" group="${5:-}"
    local as_root=""
    [ "$needs_sudo" = true ] && as_root=run_elevated

    $as_root mkdir -p "$dst_dir"

    # directory -> recurse (preserving subdirs)
    if [ -d "$src" ]; then
        local entry
        for entry in "$src"/*; do
            [ -e "$entry" ] || continue
            if [ -d "$entry" ]; then
                copy_files "$entry" "$dst_dir/$(basename "$entry")" "$needs_sudo" "$mode" "$group"
            else
                copy_files "$entry" "$dst_dir" "$needs_sudo" "$mode" "$group"
            fi
        done
        return 0
    fi

    [ -f "$src" ] || return 0
    local dst
    dst="$dst_dir/$(basename "$src")"

    # destination missing -> fresh copy
    if ! $as_root test -e "$dst"; then
        $as_root cp "$src" "$dst"
        apply_perms "$as_root" "$dst" "$mode" "$group"
        echo -e "${GREEN}+ Copied${NC} $dst ${GREEN}(new)${NC}"
        COPIED_FILES+=("$dst")
        return 0
    fi

    # identical contents -> maybe fix drifted perms, else skip
    if $as_root cmp -s "$src" "$dst"; then
        local cur_mode cur_group
        cur_mode=$($as_root stat -c '%a' "$dst")
        cur_group=$($as_root stat -c '%G' "$dst")
        if [ "$cur_mode" = "$mode" ] && { [ -z "$group" ] || [ "$cur_group" = "$group" ]; }; then
            echo -e "${YELLOW}↔ Skipping${NC} $dst ${YELLOW}(identical)${NC}"
            SKIPPED_FILES+=("$dst")
        else
            apply_perms "$as_root" "$dst" "$mode" "$group"
            echo -e "${GREEN}↻ Updated${NC} $dst ${GREEN}(permissions)${NC}"
            UPDATED_FILES+=("$dst")
        fi
        return 0
    fi

    # contents differ -> update only if the source is newer
    local src_mtime dst_mtime
    src_mtime=$(stat -c %Y "$src" 2>/dev/null)
    dst_mtime=$($as_root stat -c %Y "$dst" 2>/dev/null)
    if [ "${src_mtime:-0}" -gt "${dst_mtime:-0}" ]; then
        $as_root cp "$src" "$dst"
        apply_perms "$as_root" "$dst" "$mode" "$group"
        echo -e "${GREEN}↻ Updated${NC} $dst"
        UPDATED_FILES+=("$dst")
    else
        local dst_date src_date
        dst_date=$($as_root stat -c "%Y-%m-%d %H:%M:%S" "$dst" 2>/dev/null)
        src_date=$(stat -c "%Y-%m-%d %H:%M:%S" "$src" 2>/dev/null)
        echo -e "${RED}✗ Error${NC}: $dst is newer than source"
        echo -e "  ${RED}Dest: ${dst_date:-?} > Src: ${src_date:-?}${NC}"
        ERROR_FILES+=("$dst")
    fi
}

# host-specific file: system_configs/host-specific/<tag>/<rel> -> <dst> <args>
copy_host_file() {
    local tag="$1" rel="$2"; shift 2
    copy_files "system_configs/host-specific/$tag/$rel" "$@"
}

# --- main --------------------------------------------------------------------

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Error: do not run as root.${NC} Run as a normal wheel user."
    exit 1
fi

GIT_ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && git rev-parse --show-toplevel)"
log_verbose "${CYAN}Git root: ${GIT_ROOT}${NC}"
cd "$GIT_ROOT" || exit

if [ ! -f "$GIT_ROOT/.dotfile_tag" ]; then
    echo -e "${RED}No $GIT_ROOT/.dotfile_tag — run makesymlinks.sh first.${NC}"
    exit 1
fi
dotfile_tag="$(cat "$GIT_ROOT/.dotfile_tag")"

if [ ! -d "systemd-services" ] && [ ! -d "system_configs" ]; then
    echo -e "${RED}Error: 'systemd-services' and 'system_configs' not found.${NC}"
    exit 1
fi

run_elevated_init || exit 1

# .dotfile_tag mirrored to /etc so system services can read the active tag.
header "Dotfile tag"
run_elevated cp "$GIT_ROOT/.dotfile_tag" "/etc/dotfile_tag"
run_elevated chmod 664 "/etc/dotfile_tag"
run_elevated chgrp wheel "/etc/dotfile_tag"

# systemd units
header "Installing system services"
copy_files "systemd-services/system" "/etc/systemd/system" true "644" "root"

header "Installing user services"
USER_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$USER_CONFIG_HOME/systemd/user"
copy_files "systemd-services/user" "$USER_CONFIG_HOME/systemd/user"
if [ -d "systemd-services/user-${dotfile_tag}" ]; then
    copy_files "systemd-services/user-${dotfile_tag}" "$USER_CONFIG_HOME/systemd/user"
fi

# Make the GnuPG agent socket listen from the start of the user session so that
# pam_gnupg (run during PAM login) presets the key into the same systemd-managed
# agent that pass-secret-service later shares — preventing a dual agent and the
# first-login pinentry prompt. gpg-agent.socket is `static` (no [Install] section),
# so create the sockets.target.wants symlink by hand.
USER_SOCKETS_WANTS="$USER_CONFIG_HOME/systemd/sockets.target.wants"
mkdir -p "$USER_SOCKETS_WANTS"
ln -sfn /usr/lib/systemd/user/gpg-agent.socket "$USER_SOCKETS_WANTS/gpg-agent.socket"

# /etc and /usr config files
header "Installing system configurations"
copy_files "system_configs/etc/NetworkManager"      "/etc/NetworkManager"          true "644" "root"
copy_files "system_configs/etc/tlp.conf"            "/etc"                         true "644" "root"
copy_files "system_configs/etc/pacman.d/hooks"      "/etc/pacman.d/hooks"          true "644" "root"
copy_files "system_configs/etc/polkit-1/rules.d"    "/etc/polkit-1/rules.d"        true "644" "root"
copy_files "system_configs/usr/share/xdg-desktop-portal" "/usr/share/xdg-desktop-portal" true "644" "root"
copy_files "system_configs/etc/sudoers.d"           "/etc/sudoers.d"               true "440" "root"
copy_files "system_configs/etc/pam.d"               "/etc/pam.d"                   true "644" "root"
if [ "$dotfile_tag" = "pc" ]; then
    copy_files "system_configs/etc/systemd"         "/etc/systemd"                 true "644" "root"
fi

# host-specific (per-tag) files
if [ -f "system_configs/host-specific/$dotfile_tag/etc/wireguard/wg0.conf" ]; then
    copy_host_file "$dotfile_tag" "etc/wireguard/wg0.conf" "/etc/wireguard" true "600" "root"
fi

# reload + reseed
header "Reloading configurations"
log_verbose "${CYAN}Setting systemd stop timeout to 15s…${NC}"
run_elevated mkdir -p /etc/systemd/system.conf.d
echo -e "[Manager]\nDefaultTimeoutStopSec=15s" | run_elevated tee /etc/systemd/system.conf.d/timeout.conf > /dev/null
log_verbose "${CYAN}Reloading polkit…${NC}";       run_elevated systemctl reload polkit
log_verbose "${CYAN}Reloading system daemon…${NC}"; run_elevated systemctl daemon-reload
log_verbose "${CYAN}Reloading user daemon…${NC}";   systemctl --user daemon-reload
log_verbose "${CYAN}Enabling linger for ${USER}…${NC}"; run_elevated loginctl enable-linger "$USER"

header "Enabling services"
enable_service git-reminder.timer
enable_service check_for_docker_updates.timer
enable_service --user git-reminder.timer
enable_service --user dunst.service
[ "$dotfile_tag" = "pc" ]       && enable_service --user vps-socks.service
[ "$dotfile_tag" = "hackerman" ] && enable_service --user keyboard-remap.service
enable_service atd

# summary (counts always; detailed lists under VERBOSE)
echo
echo -e "${BOLD}File operations:${NC}  ${GREEN}+${NC}${#COPIED_FILES[@]} new  ${GREEN}↻${NC}${#UPDATED_FILES[@]} updated  ${YELLOW}↔${NC}${#SKIPPED_FILES[@]} skipped  ${RED}✗${NC}${#ERROR_FILES[@]} errors"
echo -e "${BOLD}Services:${NC}         ${GREEN}✓${NC}${#ENABLED_SERVICES[@]} enabled  ${GREEN}▶${NC}${#STARTED_SERVICES[@]} started"

if [ "${VERBOSE:-0}" -eq 1 ]; then
    [ ${#COPIED_FILES[@]} -gt 0 ]     && { echo -e "\n${BOLD}New files:${NC}";      printf '  %s\n' "${COPIED_FILES[@]}"; }
    [ ${#UPDATED_FILES[@]} -gt 0 ]    && { echo -e "\n${BOLD}Updated files:${NC}";   printf '  %s\n' "${UPDATED_FILES[@]}"; }
    [ ${#ENABLED_SERVICES[@]} -gt 0 ] && { echo -e "\n${BOLD}Enabled services:${NC}";printf '  %s\n' "${ENABLED_SERVICES[@]}"; }
fi

echo
if [ ${#ERROR_FILES[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ System configuration applied successfully!${NC}"
else
    echo -e "${YELLOW}${BOLD}⚠ Applied with warnings — check the errors above.${NC}"
fi

run_elevated_cleanup
