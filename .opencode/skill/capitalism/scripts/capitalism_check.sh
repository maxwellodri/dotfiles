#!/usr/bin/env bash
set -euo pipefail

BINARY="/usr/bin/chromium"
ERRORS=()

if ! test -x "$BINARY"; then
    ERRORS+=("chromium not found at $BINARY — install with: paru -S ungoogled-chromium-bin")
fi

if pgrep -f chromium &>/dev/null; then
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
echo "  If browser tools are not available, enable the playwright MCP"
echo "  in .config/opencode/opencode.json and restart opencode."
echo ""
echo "Config uses a dedicated config file:"
echo '  "playwright": {'
echo '    "type": "local",'
echo '    "command": ["npx", "@playwright/mcp@latest",'
echo '      "--config", "~/.opencode/skill/capitalism/playwright-config.json"],'
echo '    "enabled": true'
echo '  }'
