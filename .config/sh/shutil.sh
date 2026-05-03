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

check_kernel() {
    if ! command -v pacman >/dev/null 2>&1; then
        return 0
    fi

    running_kernel=$(uname -r)
    installed_kernel=$(pacman -Qi linux 2>/dev/null | grep '^Version' | awk '{print $3}')

    if [ -z "$installed_kernel" ]; then
        return 0
    fi

    running_normalized=$(echo "$running_kernel" | sed 's/\.arch/-arch/')
    installed_normalized=$(echo "$installed_kernel" | sed 's/\.arch/-arch/')

    if [ "$running_normalized" != "$installed_normalized" ]; then
        echo "Kernel version mismatch detected:" >&2
        echo "  Running:   $running_kernel" >&2
        echo "  Installed: $installed_kernel" >&2
        echo "Reboot required." >&2
        return 1
    fi

    return 0
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
    if [ -n "${SHUTIL_PREFER_GUI:-}" ]; then
        case $(display_kind) in
            wl|x11) pkexec "$@" ;;
            *) sudo "$@" ;;
        esac
    else
        sudo "$@"
    fi
}

run_elevated_init() {
    if [ -n "${SHUTIL_PREFER_GUI:-}" ]; then
        return 0
    fi
    if ! sudo -v; then
        return 1
    fi
    (
        while true; do sudo -n true; sleep 50; done
    ) &
    _SHUTIL_KEEPALIVE_PID=$!
}

run_elevated_cleanup() {
    kill "$_SHUTIL_KEEPALIVE_PID" 2>/dev/null
}
