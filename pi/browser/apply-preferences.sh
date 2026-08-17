#!/usr/bin/env bash
# Seed the Playwright-MCP ungoogled-chromium profile(s) with dotfiles-managed
# prefs (pi/browser/preferences.json).
#
# The profile dir name (~/.cache/ms-playwright-mcp/mcp-chrome-<hash>) is derived
# from the MCP config, so it CHANGES whenever playwright-config.json changes.
# Run this script after any config change (or first browser launch) to re-apply
# the download-directory pref.
#
# Must run while the MCP chromium is CLOSED (it rewrites Preferences on exit).
set -euo pipefail

seed="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/preferences.json"
roots=("${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright-mcp" "$HOME/.cache/ms-playwright")

# Chromium/MCP create this on demand, but pre-create so downloads never fail.
mkdir -p "$HOME/Downloads/pi"

found=0
for root in "${roots[@]}"; do
	for profile in "$root"/mcp-chrome-*; do
		[ -d "$profile" ] || continue
		if pgrep -f -- "--user-data-dir=$profile" >/dev/null 2>&1; then
			echo "SKIP: $profile (chromium is running — close it first)" >&2
			continue
		fi
		found=1
		prefs="$profile/Default/Preferences"
		mkdir -p "$profile/Default"
		[ -f "$prefs" ] || echo '{}' >"$prefs"
		tmp="$prefs.tmp"
		jq --slurpfile s "$seed" '. * $s[0]' "$prefs" >"$tmp"
		mv "$tmp" "$prefs"
		echo "seeded: $prefs"
	done
done

if [ "$found" -eq 0 ]; then
	echo "No MCP chromium profile found yet — one is created on first browser launch." >&2
	echo "Make any playwright MCP call, close the browser, then re-run this script." >&2
fi
