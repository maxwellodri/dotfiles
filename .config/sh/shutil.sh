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
    suffix=$(echo "$running_kernel" | sed 's/[0-9]\+\.[0-9]\+\.[0-9]\+-[0-9]\+//')
    case "$suffix" in
        -lts) pkg="linux-lts" ;;
        -zen) pkg="linux-zen" ;;
        -hardened) pkg="linux-hardened" ;;
        -rt) pkg="linux-rt" ;;
        *) pkg="linux" ;;
    esac

    installed_kernel=$(pacman -Qi "$pkg" 2>/dev/null | grep '^Version' | awk '{print $3}')

    if [ -z "$installed_kernel" ]; then
        return 0
    fi

    running_base=$(echo "$running_kernel" | sed "s/${suffix}$//")
    running_normalized=$(echo "$running_base" | sed 's/\.arch/-arch/')
    installed_normalized=$(echo "$installed_kernel" | sed 's/\.arch/-arch/')

    if [ "$running_normalized" != "$installed_normalized" ]; then
        echo "Kernel version mismatch detected ($pkg):" >&2
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

symlink_contents() {
    _sc_src=""
    _sc_target=""
    _sc_excludes=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --exclude)
                shift
                _sc_excludes="$_sc_excludes $1"
                shift
                ;;
            *)
                if [ -z "$_sc_src" ]; then
                    _sc_src="$1"
                elif [ -z "$_sc_target" ]; then
                    _sc_target="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$_sc_src" ] || [ -z "$_sc_target" ]; then
        echo "Usage: symlink_contents <src_dir> <target_dir> [--exclude <glob>]..." >&2
        return 1
    fi

    if [ ! -d "$_sc_src" ]; then
        echo "Error: source directory '$_sc_src' does not exist" >&2
        return 1
    fi

    mkdir -p "$_sc_target"

    for _sc_entry in "$_sc_src"/*; do
        [ -e "$_sc_entry" ] || continue

        _sc_name="$(basename "$_sc_entry")"

        _sc_skip=false
        for _sc_pat in $_sc_excludes; do
            case "$_sc_name" in
                $_sc_pat) _sc_skip=true; break ;;
            esac
        done
        [ "$_sc_skip" = true ] && continue

        ln -sf "$_sc_entry" "$_sc_target/"
        echo "Linked $_sc_name -> $_sc_target"
    done
}
