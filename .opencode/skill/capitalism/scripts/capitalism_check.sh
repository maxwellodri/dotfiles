#!/usr/bin/env bash
set -euo pipefail

BINARY="/usr/bin/ungoogled-chromium"
ERRORS=()

if ! command -v "$BINARY" &>/dev/null; then
    ERRORS+=("ungoogled-chromium not found at $BINARY — install with: paru -S ungoogled-chromium")
fi

if pgrep -f "$BINARY" &>/dev/null; then
    echo "NOTE: ungoogled-chromium is already running (session may be reusable)"
else
    echo "OK: ungoogled-chromium is not running (Playwright MCP will spawn it)"
fi

if ! command -v npx &>/dev/null; then
    ERRORS+=("npx not found — install Node.js to run Playwright MCP")
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "FAIL: capitalism skill cannot proceed"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi

echo "PASS: ungoogled-chromium ready"
echo ""
echo "NOTE: Playwright MCP must be enabled in opencode.json."
echo "  If browser tools are not available, add the playwright MCP config"
echo "  to .config/opencode/opencode.json and restart opencode."
echo ""
echo "Config to add:"
echo '  "playwright": {'
echo '    "type": "local",'
echo '    "command": ["npx", "@playwright/mcp@latest",'
echo '      "--executable-path", "/usr/bin/ungoogled-chromium"],'
echo '    "enabled": true'
echo '  }'
