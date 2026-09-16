#!/usr/bin/env bash
# browser-snapshot.sh — promote a chromium profile into the shared template
# that future pi browser sessions are cloned from (see
# pi/extensions/browser-profiles.ts + .pi/skills/web-browser-use/TECHNICAL_DETAILS.md).
#
# Usage:
#   browser-snapshot.sh              # snapshot CURRENT pi session's browser
#   browser-snapshot.sh <session-id> # snapshot that session's browser
#   browser-snapshot.sh <dir>        # snapshot an explicit profile dir
#   browser-snapshot.sh --yes ...    # skip the confirmation prompt
#
# Semantics:
#   • MERGING (rsync without --delete): logins/cookies/extensions already in
#     the template are kept; the source's state is layered on top. Snapshot
#     from any session to accumulate state over time.
#   • Volatile caches/locks/session-restore state never cross the boundary
#     (same EXCLUDES as browser-profiles.ts, plus session junk).
#   • MANUAL ONLY — nothing here runs automatically, ever.
#
# Workflow:
#   1. Interact with a session's browser (log in, install, set defaults).
#   2. Close that browser (playwright_browser_close or close the window) —
#      Chromium must exit so cookies/storage are flushed to disk.
#   3. Run this script; confirm.
#   4. Future sessions clone the updated template. Already-running sessions
#      keep their old clone until they end.
set -euo pipefail

yes=0
[[ "${1:-}" == "--yes" ]] && { yes=1; shift; }

template="${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright-mcp/mcp-chrome-template"
sessions_root="/tmp/pi/chromium"

if [[ $# -ge 1 ]]; then
	if [[ -d "$1" ]]; then
		src="$(realpath "$1")"
	else
		src="$sessions_root/$1"
	fi
elif [[ -n "${PI_SESSION_FILE:-}" ]]; then
	sid="$(basename "$PI_SESSION_FILE" .jsonl | sed 's/^[^_]*_//')"
	src="$sessions_root/$sid"
else
	echo "error: pass a <session-id> or <dir>, or run from a pi bash tool (PI_SESSION_FILE)" >&2
	exit 1
fi

if [[ ! -d "$src" ]]; then
	echo "error: source profile not found: $src" >&2
	echo "known sessions:" >&2
	find "$sessions_root" -maxdepth 1 -mindepth 1 -printf '  %f\n' 2>/dev/null >&2
	exit 1
fi

if [[ ! -d "$template" ]]; then
	echo "error: template missing: $template" >&2
	exit 1
fi

for dir in "$src" "$template"; do
	if pgrep -f -- "--user-data-dir=$dir" >/dev/null 2>&1; then
		echo "error: chromium is running on $dir — close it first (state must be flushed)" >&2
		exit 1
	fi
done

size="$(du -sh "$src" | cut -f1)"
echo "snapshot (merge):"
echo "  from: $src ($size)"
echo "  to:   $template"
if [[ $yes -ne 1 ]]; then
	read -r -p "promote this state to the template? [y/N] " reply
	[[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted"; exit 0; }
fi

rsync -a \
	--exclude 'Singleton*' --exclude lockfile \
	--exclude 'Default/Cache' --exclude 'Default/Code Cache' \
	--exclude 'Default/GPUCache' --exclude 'Default/GraphiteDawnCache' \
	--exclude 'Default/Service Worker/CacheStorage' \
	--exclude 'GraphiteDawnCache' --exclude 'GrShaderCache' --exclude 'ShaderCache' \
	--exclude 'crash_interval' \
	--exclude 'Default/Sessions' --exclude 'Default/Session Storage' \
	--exclude 'Default/Top Sites' --exclude 'Crashpad' \
	"$src/" "$template/"

echo "done — future sessions inherit this state."
