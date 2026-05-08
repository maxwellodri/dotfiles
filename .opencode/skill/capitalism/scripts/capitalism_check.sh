#!/usr/bin/env bash
set -euo pipefail

ERRORS=()
WARNINGS=()

for cmd in curl jq pass; do
    if ! command -v "$cmd" &>/dev/null; then
        ERRORS+=("$cmd is not installed — required by websearch")
    fi
done

if [ ${#ERRORS[@]} -eq 0 ]; then
    if ! pass brave_search_api_key &>/dev/null; then
        ERRORS+=("brave_search_api_key not found in pass — run: pass insert brave_search_api_key")
    fi
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "FAIL: capitalism skill cannot proceed"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi

echo "PASS: websearch ready (curl, jq, pass with brave_search_api_key)"
echo ""

BINARY="/usr/bin/chromium"
if ! test -x "$BINARY"; then
    WARNINGS+=("chromium not found at $BINARY — Playwright deep-dive unavailable (install: paru -S ungoogled-chromium-bin)")
fi

if ! command -v npx &>/dev/null; then
    WARNINGS+=("npx not found — Playwright deep-dive unavailable (install Node.js)")
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "WARN: Playwright deep-dive is optional but unavailable"
    for w in "${WARNINGS[@]}"; do
        echo "  - $w"
    done
    echo ""
    echo "The skill works fully without Playwright using websearch alone."
    echo "Playwright is only needed for scraping individual store pages when"
    echo "websearch results lack sufficient detail (specs, shipping, stock)."
else
    echo "PASS: Playwright MCP ready (optional deep-dive tool)"
    echo ""
    echo "Playwright MCP must be enabled by the user if needed."
    echo "  Enable the playwright MCP in the opencode TUI, then confirm when ready."
fi
