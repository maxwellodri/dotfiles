#!/bin/sh
############################
# Bootstraps pi (pi.dev) on a fresh machine.
#  - Already installed -> report and skip the installer.
#  - Missing -> ensure pacman deps (nodejs, npm, uv), then run the official
#    pi.dev installer with our committed npmrc in force.
#  - Always -> (re)install the vendored pi-mcp-adapter deps if missing
#    (node_modules is gitignored by design; see pi/.gitignore).
############################

dir="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)"
. "$dir/.config/sh/shutil.sh"

# pi.dev's installer derives its install location from `npm prefix -g` at
# install time (falls back to ~/.local when that's not user-writable — how pc
# ended up with ~/.local/bin/pi while hackerman got $XDG_DATA_HOME/npm/bin/pi).
# The committed npmrc pins the prefix to $XDG_DATA_HOME/npm, and it references
# ${XDG_*_HOME}, so export XDG defaults (a bootstrap sh doesn't source
# .zprofile like interactive zsh does) AND point npm at our npmrc BEFORE any
# npm call. Makes installs deterministic and identical across machines.
: "${XDG_DATA_HOME:=$HOME/.local/share}";  export XDG_DATA_HOME
: "${XDG_CACHE_HOME:=$HOME/.cache}";       export XDG_CACHE_HOME
: "${XDG_STATE_HOME:=$HOME/.local/state}"; export XDG_STATE_HOME
: "${XDG_CONFIG_HOME:=$HOME/.config}";     export XDG_CONFIG_HOME
if [ -f "$XDG_CONFIG_HOME/npm/npmrc" ]; then
    export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
fi

# Installed check: probe known locations only. Never `command -v pi` —
# makesymlinks.sh puts this repo's wrapper (scripts/pi) on PATH as ~/bin/pi,
# which would always match (and the wrapper recurses into itself).
pi_bin="${PI_BIN:-}"
if [ -z "$pi_bin" ]; then
    for candidate in "$XDG_DATA_HOME/npm/bin/pi" "$HOME/.local/bin/pi"; do
        if [ -x "$candidate" ]; then
            pi_bin="$candidate"
            break
        fi
    done
fi

if [ -n "$pi_bin" ]; then
    echo "Pi is already installed ($pi_bin)"
else
    echo "Installing pi..."

    # pacman deps: nodejs/npm (pi is an npm-distributed bundle; its installer
    # refuses to run without npm) and uv (pi/mcp.json's blender server runs
    # via `uv run`; uv also manages that project's Python interpreter).
    if command -v pacman >/dev/null 2>&1; then
        missing=""
        for pkg in nodejs npm uv; do
            pacman -Q "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
        done
        if [ -n "$missing" ]; then
            echo "Installing pacman packages:$missing"
            run_elevated pacman -S --needed $missing || exit 1
        fi
    fi

    if ! command -v npm >/dev/null 2>&1; then
        echo "npm unavailable — pi.dev installer requires it" >&2
        exit 1
    fi

    curl -fsSL https://pi.dev/install.sh | sh
fi

# Vendored extension deps are gitignored (reinstalled per machine). Running
# this on every bootstrap regardless of the pi check above: pi can be
# installed while a fresh dotfiles clone lacks node_modules — exactly how the
# mcp adapter broke on hackerman. npm ci is a no-op-fast check when present.
adapter="$dir/pi/vendor/pi-mcp-adapter"
if [ -f "$adapter/package.json" ] && command -v npm >/dev/null 2>&1; then
    if [ ! -d "$adapter/node_modules" ]; then
        echo "Installing vendored pi-mcp-adapter deps..."
        (cd "$adapter" && npm ci --omit=dev)
    fi
fi
