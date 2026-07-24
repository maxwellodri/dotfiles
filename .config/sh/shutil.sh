#!/bin/sh

display_kind() {
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        echo "wl"
    elif [ -n "${DISPLAY:-}" ]; then
        echo "x11"
    else
        echo "tty"
    fi
}

# Detect a stale running kernel (common after `pacman -Syu` with no reboot).
# Compares `uname -r` against the version `pacman -Q` reports for the matching
# linux package. Returns 0 when in sync, 1 (with a notice on stderr unless
# SHUTIL_QUIET is set) when a reboot is needed.
#
# Each supported flavor is its own case arm: to add one, just give its package
# name and the ABI suffix to strip. Flavor is inferred from the last hyphen-
# segment of uname, e.g.
#   7.1.4-zen1-1-zen  -> zen
#   6.18.39-1-lts     -> lts
#   6.11.8-arch1-1    -> 1   (stock; falls through to the default arm)
check_kernel() {
    [ -n "$(command -v pacman 2>/dev/null)" ] || return 0

    _ck_running=$(uname -r)
    _ck_tail=${_ck_running##*-}

    case "$_ck_tail" in
        zen)      _ck_pkg=linux-zen;       _ck_suffix=-zen ;;
        lts)      _ck_pkg=linux-lts;       _ck_suffix=-lts ;;
        hardened) _ck_pkg=linux-hardened;  _ck_suffix=-hardened ;;
        rt)       _ck_pkg=linux-rt;        _ck_suffix=-rt ;;
        *)        _ck_pkg=linux;           _ck_suffix= ;;  # stock Arch kernel
    esac

    _ck_line=$(pacman -Q "$_ck_pkg" 2>/dev/null) || return 0
    _ck_installed=${_ck_line##* }

    # uname and pacman render the version with different separators (e.g.
    # "7.1.4-zen1-1-zen" vs "7.1.4.zen1-1"); drop the ABI suffix from the
    # running string, then unify dots and dashes so the two line up.
    _ck_run_norm=$(printf '%s' "${_ck_running%"$_ck_suffix"}" | tr '.' '-')
    _ck_inst_norm=$(printf '%s' "$_ck_installed" | tr '.' '-')

    [ "$_ck_run_norm" = "$_ck_inst_norm" ] && return 0

    if [ -z "${SHUTIL_QUIET:-}" ]; then
        echo "Kernel version mismatch detected ($_ck_pkg):" >&2
        echo "  Running:   $_ck_running" >&2
        echo "  Installed: $_ck_installed" >&2
        echo "Reboot required." >&2
    fi
    return 1
}

get_dmenu() {
    case $(display_kind) in
        wl) echo "dmenu-wl" ;;
        x11) echo "dmenu" ;;
        tty) echo "fzf" ;;
    esac
}

get_imgviewer() {
    case $(display_kind) in
        wl) echo "imv" ;;
        x11) echo "feh" ;;
        tty) echo "No display server detected" >&2; return 1 ;;
    esac
}

run_elevated() {
    if [ -n "${SHUTIL_PREFER_GUI:-}" ] && [ "$(display_kind)" != "tty" ]; then
        SUDO_ASKPASS="${SHUTIL_SUDO_ASKPASS:-$HOME/bin/sudo-askpass-dotfiles}" sudo -A "$@"
    else
        sudo "$@"
    fi
}

run_elevated_init() {
    if [ -n "${SHUTIL_PREFER_GUI:-}" ] && [ "$(display_kind)" != "tty" ]; then
        SUDO_ASKPASS="${SHUTIL_SUDO_ASKPASS:-$HOME/bin/sudo-askpass-dotfiles}" sudo -A -v || return 1
    else
        sudo -v || return 1
    fi
    (
        while true; do sudo -n true; sleep 50; done
    ) &
    _SHUTIL_KEEPALIVE_PID=$!
}

run_elevated_cleanup() {
    kill "$_SHUTIL_KEEPALIVE_PID" 2>/dev/null
}

symlink_contents() {
    _SHUTIL_SRC=""
    _SHUTIL_TARGET=""
    _SHUTIL_EXCLUDES=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --exclude)
                shift
                _SHUTIL_EXCLUDES="$_SHUTIL_EXCLUDES $1"
                shift
                ;;
            *)
                if [ -z "$_SHUTIL_SRC" ]; then
                    _SHUTIL_SRC="$1"
                elif [ -z "$_SHUTIL_TARGET" ]; then
                    _SHUTIL_TARGET="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$_SHUTIL_SRC" ] || [ -z "$_SHUTIL_TARGET" ]; then
        echo "Usage: symlink_contents <src_dir> <target_dir> [--exclude <glob>]..." >&2
        return 1
    fi

    if [ ! -d "$_SHUTIL_SRC" ]; then
        echo "Error: source directory '$_SHUTIL_SRC' does not exist" >&2
        return 1
    fi

    mkdir -p "$_SHUTIL_TARGET"

    for _SHUTIL_ENTRY in "$_SHUTIL_SRC"/*; do
        [ -e "$_SHUTIL_ENTRY" ] || continue

        _SHUTIL_NAME="$(basename "$_SHUTIL_ENTRY")"

        _SHUTIL_SKIP=false
        for _SHUTIL_PAT in $_SHUTIL_EXCLUDES; do
            case "$_SHUTIL_NAME" in
                $_SHUTIL_PAT) _SHUTIL_SKIP=true; break ;;
            esac
        done
        [ "$_SHUTIL_SKIP" = true ] && continue

        _SHUTIL_DEST="$_SHUTIL_TARGET/$_SHUTIL_NAME"
        if [ -e "$_SHUTIL_DEST" ] && [ ! -L "$_SHUTIL_DEST" ]; then
            echo "Found regular file $_SHUTIL_NAME, skipping..." >&2
            continue
        fi

        ln -sf "$_SHUTIL_ENTRY" "$_SHUTIL_TARGET/"
        echo "Linked $_SHUTIL_NAME -> $_SHUTIL_TARGET"
    done
}

prune_dead_symlinks() {
    _SHUTIL_PRUNE_DIR=""
    _SHUTIL_PRUNE_SRC=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --source)
                shift
                _SHUTIL_PRUNE_SRC="$1"
                shift
                ;;
            *)
                if [ -z "$_SHUTIL_PRUNE_DIR" ]; then
                    _SHUTIL_PRUNE_DIR="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$_SHUTIL_PRUNE_DIR" ]; then
        echo "Usage: prune_dead_symlinks <dir> [--source <src_dir>]" >&2
        return 1
    fi

    if [ ! -d "$_SHUTIL_PRUNE_DIR" ]; then
        echo "Error: directory '$_SHUTIL_PRUNE_DIR' does not exist" >&2
        return 1
    fi

    for _SHUTIL_PRUNE_ENTRY in "$_SHUTIL_PRUNE_DIR"/*; do
        [ -L "$_SHUTIL_PRUNE_ENTRY" ] || continue

        _SHUTIL_PRUNE_TARGET="$(readlink -f "$_SHUTIL_PRUNE_ENTRY")"

        if [ -n "$_SHUTIL_PRUNE_SRC" ]; then
            case "$_SHUTIL_PRUNE_TARGET" in
                "$_SHUTIL_PRUNE_SRC"/*) ;;
                *) continue ;;
            esac
        fi

        if [ ! -e "$_SHUTIL_PRUNE_TARGET" ]; then
            _SHUTIL_PRUNE_BASENAME="$(basename "$_SHUTIL_PRUNE_ENTRY")"
            rm "$_SHUTIL_PRUNE_ENTRY"
            echo "Pruned dead symlink: $_SHUTIL_PRUNE_BASENAME"
        fi
    done
}
