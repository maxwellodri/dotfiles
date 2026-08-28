# Technical details: playwright MCP ↔ per-session chromium

How the web-browser-use skill's browser isolation works under the hood.

## Problem

`@playwright/mcp` launches one persistent chromium per MCP server process,
keyed on the client cwd — every pi session shares `pi/browser` as cwd, so all
landed on the same profile dir and collided on Chromium's `SingletonLock`
("Browser is already in use …"). One profile dir can only ever be owned by one
live chromium process; that is a Chromium design constraint, not a Playwright
one.

(Chromium *can* run one process with many windows sharing one profile, but
over CDP a non-isolated MCP client gets `contexts()[0]` — the entire shared tab
set — so agents would see/close each other's tabs. Rejected.)

## Solution: per-session clones of a shared template

- `pi/extensions/browser-profiles.ts` (auto-discovered, `/reload`able) runs on
  `session_start`:
  1. Session profile dir: `/tmp/pi/chromium/<session-id>` (tmpfs → free GC on
     reboot; a resumed session reuses its dir within the same boot).
  2. If new, `rsync -a` it from the template, excluding volatile/bulky state
     (`Singleton*`, `lockfile`, `Default/Cache`, `Default/Code Cache`,
     `Default/GPUCache`, `GraphiteDawnCache`, `GrShaderCache`, `ShaderCache`,
     Service Worker cache storage). Clone ≈ 90 MB in RAM, < 1 s.
  3. Seed prefs (`pi/browser/preferences.json`: download dir `~/Downloads/pi`)
     into `Default/Preferences` — same merge `apply-preferences.sh` does.
  4. `process.env.PI_BROWSER_PROFILE_DIR = <dir>`.
- `pi/mcp.json` (playwright entry) passes it through:
  `"env": { "PLAYWRIGHT_MCP_USER_DATA_DIR": "${PI_BROWSER_PROFILE_DIR}" }`.
  In `@playwright/mcp` ≥ 0.0.78 env overrides the `--config` JSON file
  (precedence: defaults < config file < `PLAYWRIGHT_MCP_*` env < CLI flags),
  and an explicit `userDataDir` bypasses the cwd-hashed default dir entirely.
- Timing is safe: pi only injects `PI_SESSION_ID`/`PI_SESSION_FILE` into
  bash-tool execs, not its own `process.env`, hence the extension sets the
  profile var itself. MCP servers are lazy — spawned on first browser use,
  always after `session_start`.
- Subagents are separate `pi` child processes; they run their own
  `session_start` and thus get their own clone.
- If `PI_BROWSER_PROFILE_DIR` is somehow unset, the interpolated env value is
  the empty string, which `@playwright/mcp` treats as unset → falls back to
  stock (shared-hash) behavior.

## Template

- Location: `~/.cache/ms-playwright-mcp/mcp-chrome-template` (matches the
  `mcp-chrome-*` glob used by `pi/browser/apply-preferences.sh`).
- Manage it: `pi/user-scripts/browser-template.sh` (deliberately in
  `pi/user-scripts/`, not PATH'd `pi/scripts/`) — opens chromium on the
  template; log in, close. New sessions inherit those logins.
- Caveat: clones taken while the template window is open may miss the most
  recent unflushed logins (SQLite write-back lag). Clone with it closed.
- Bootstrapped from the pre-existing live profile `mcp-chrome-7e9eb7e`.
- Promote a session's logins back to the template later if ever needed
  (not implemented): rsync `/tmp/pi/chromium/<sid>/` → template, browser closed.

## Semantics

- Logins/cookies/extensions made *during* a session are private to it and last
  for that session's lifetime (same boot, incl. `pi --resume`).
- After `/resume` or `/new`, an already-connected playwright server keeps the
  previous session's profile until `/mcp reconnect playwright` or its idle
  timeout — expected, harmless.
- `playwright_browser_close` closes only that session's chromium.

## Relevant upstream facts (playwright-mcp 0.0.78, verified in source)

- Default profile: `~/.cache/ms-playwright-mcp/mcp-<browserToken>-<sha256(client cwd)[0:7]>`.
- Singleton conflict → `isProfileLocked5Times` → "Browser is already in use …
  use --isolated".
- `--isolated` / `PLAYWRIGHT_MCP_ISOLATED` = in-memory profile per client
  (no persistence, no pref seeding) — the fallback option.
- Context selection per client: `isolated ? browser.newContext() :
  browser.contexts()[0]` (why shared-CDP was rejected).
- Upstream README's own guidance for concurrent clients: `--isolated` or a
  distinct `--user-data-dir` each. Feature requests for real multi-session
  sharing: microsoft/playwright#40585, playwright-mcp#1294, #1530 (fork:
  `playwright-mcp-sessions`).
