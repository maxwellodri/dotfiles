#!/usr/bin/env bash
# browser-template.sh — open the shared chromium template profile that pi
# browser sessions are cloned from (see pi/extensions/browser-profiles.ts).
#
# Log into the sites your agents should have access to, then close the
# window. New pi sessions (and subagents) clone this profile at session
# start, so they inherit its logins, cookies and extensions.
#
# Sessions started WHILE this window is open may miss the most recent
# unflushed logins — prefer logging in, closing, then starting sessions.
#
# Rarely used by hand: deliberately NOT on PATH (unlike pi/scripts/).
set -euo pipefail

template="${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright-mcp/mcp-chrome-template"
mkdir -p "$template"

exec /usr/bin/chromium --user-data-dir="$template" "$@"
