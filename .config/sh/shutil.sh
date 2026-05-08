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

    shutil_running_kernel=$(uname -r)
    shutil_suffix=$(echo "$shutil_running_kernel" | sed 's/[0-9]\+\.[0-9]\+\.[0-9]\+-[0-9]\+//')
    case "$shutil_suffix" in
        -lts) shutil_pkg="linux-lts" ;;
        -zen) shutil_pkg="linux-zen" ;;
        -hardened) shutil_pkg="linux-hardened" ;;
        -rt) shutil_pkg="linux-rt" ;;
        *) shutil_pkg="linux" ;;
    esac

    shutil_installed_kernel=$(pacman -Qi "$shutil_pkg" 2>/dev/null | grep '^Version' | awk '{print $3}')

    if [ -z "$shutil_installed_kernel" ]; then
        return 0
    fi

    shutil_running_base=$(echo "$shutil_running_kernel" | sed "s/${shutil_suffix}$//")
    shutil_running_normalized=$(echo "$shutil_running_base" | sed 's/\.arch/-arch/')
    shutil_installed_normalized=$(echo "$shutil_installed_kernel" | sed 's/\.arch/-arch/')

    if [ "$shutil_running_normalized" != "$shutil_installed_normalized" ]; then
        echo "Kernel version mismatch detected ($shutil_pkg):" >&2
        echo "  Running:   $shutil_running_kernel" >&2
        echo "  Installed: $shutil_installed_kernel" >&2
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
