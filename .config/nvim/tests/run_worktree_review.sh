#!/usr/bin/env bash
# Run the WorktreeReview headless spec in an isolated XDG environment.
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_CONFIG_HOME=/tmp/wtr-spec-xdg/config
export XDG_DATA_HOME=/tmp/wtr-spec-xdg/data
export XDG_STATE_HOME=/tmp/wtr-spec-xdg/state
export XDG_CACHE_HOME=/tmp/wtr-spec-xdg/cache
rm -rf /tmp/wtr-spec-xdg
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
exec nvim --headless -u tests/minimal_init.lua -c 'luafile tests/worktree_review_spec.lua'
