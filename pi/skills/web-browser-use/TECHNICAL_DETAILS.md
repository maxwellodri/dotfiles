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

- `pi/extensions/browser-profiles.ts` (auto-discovered, `/reload`able):
  1. `session_start`: mkdir the session profile dir
     `/tmp/pi/chromium/<session-id>` (tmpfs → free GC on reboot) and GC dirs
     untouched for >3d (crash orphans, shutdown skips). Nothing is copied yet —
     most sessions never use the browser, so the ~112MB clone is lazy. Then
     register the playwright MCP server (pi's builtin MCP, exposure
     `deferred`) with `PLAYWRIGHT_MCP_USER_DATA_DIR` set to the profile dir
     **inline** — the dir is known before registration, so there is no
     env-var timing to get right.
  2. `tool_call` (first playwright MCP use — the hook can block, so the clone
     lands before chromium, which the server launches only on the first
     browser tool call, reads the dir): `rsync -a` from the template, excluding
     volatile/bulky state (`Singleton*`, `lockfile`, `Default/Cache`,
     `Default/Code Cache`, `Default/GPUCache`, `GraphiteDawnCache`,
     `GrShaderCache`, `ShaderCache`, Service Worker cache storage). Then seed
     prefs (`pi/browser/preferences.json`: download dir `~/Downloads/pi`)
     into `Default/Preferences` — same merge `apply-preferences.sh` does.
     On rsync failure the partial dir is dropped (truly clean profile, not a
     half-clone) and the warning carries rsync's stderr first line. A clone
     from the same boot (`pi --resume`, `/reload`) is detected via its
     `Local State` marker and reused as-is.
  3. `session_shutdown` (`"quit"`/`"new"`/`"resume"`/`"fork"`): delete the
     profile dir — skipped for `"reload"` (same session continues;
     un-snapshotted logins kept) and while a chromium still runs on it; the
     >3d GC collects skips later.
- The server config lives in `browser-profiles.ts`, **not** `pi/mcp.json`:
  `mcp.json` is shared to every host via the repo, and pi's builtin MCP
  connects every configured server at session start — a file-configured
  server would spawn `npx` on machines that never browse. Registration is
  gated on `/usr/bin/chromium` existing (the executablePath the config
  pins), so only browser-capable machines get the server. In
  `@playwright/mcp` ≥ 0.0.78 env overrides the `--config` JSON file
  (precedence: defaults < config file < `PLAYWRIGHT_MCP_*` env < CLI flags),
  and an explicit `userDataDir` bypasses the cwd-hashed default dir entirely.
- Timing: the MCP **server process** spawns at registration (session start);
  chromium itself launches inside the server on the first browser tool call
  — the same tool call whose `tool_call` hook blocks on the clone, so the
  profile dir is complete before chromium reads it.
- Subagents are separate `pi` child processes; they run their own
  `session_start`/`session_shutdown` and thus get their own profile dir,
  lazily cloned on their own first browser use.

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

- Logins/cookies/extensions made *during* a session are private to it and
  last until the session ends (`session_shutdown` deletes the dir; state you
  want to keep must be promoted via `browser-snapshot.sh` before exiting).
  `/reload` and a same-boot `pi --resume` of a session that never cleanly
  exited reuse the existing dir (its `Local State` marker).
- `mcp__playwright__browser_close` closes only that session's chromium.

## Snapshot workflow (promote session state → template)

`pi/user-scripts/browser-snapshot.sh` — MANUAL ONLY, never automatic:

```sh
browser-snapshot.sh              # snapshot the CURRENT pi session's browser
browser-snapshot.sh <session-id> # any session under /tmp/pi/chromium/
browser-snapshot.sh <dir>        # any explicit chromium profile dir
```

1. Interact with a session's browser (log in, install, set defaults).
2. Close that browser first — the script refuses to run while chromium holds
   the source (or template) profile, since cookies/storage flush on exit.
   NB: `playwright_browser_close` closes the page but leaves the chromium
   PROCESS alive holding the profile — kill the main proc (pgrep -f
   "--user-data-dir=<profile>" | kill non-`--type=` procs); the next MCP
   navigate respawns the browser cleanly.
3. Confirm the prompt (`--yes` to skip).

Semantics: **merging** rsync (no `--delete`) — the template keeps state it
already has; snapshots layer on top, so you can accumulate logins from
several sessions. Same EXCLUDES as the clone path, plus session-restore junk
(`Default/Sessions`, `Session Storage`, `Top Sites`, `Crashpad`) so a
snapshot's open tabs don't become the template's startup tabs.

## VDH welcome tab (patched 2026-09-16)

VDH is loaded via `--load-extension`, which Chromium treats as a **fresh
install on every browser start** → `runtime.onInstalled(reason:"install")`
→ VDH opens `downloadhelper.net/welcome` each session. (Persisting it as a
properly-installed unpacked extension via a hand-written `Preferences` entry
does NOT work — modern Chromium ignores/prunes it; tested.)

Fix (THREE parts — all required):
1. Patched the local unpacked copy at
   `~/.local/share/pi-browser-extensions/vdh/service/main.js` — in the
   `onInstalled` listener, the `install` branch no longer calls
   `tabs.create` (only sets `first_version_installed`), and the `update`
   branch no longer opens the changelog (`(a||u)&&tabs.create({url:xm})` →
   `void(a||u)`).

2026-09-18 regression: `install_flake.sh` re-downloaded VDH (dir was
missing → fresh 10.5.49.2), silently reverting the patch and the welcome
tab returned. Fixed again (10.5.49.2 → 10.5.49.3), and `install_flake.sh`
now auto-applies this patch + version bump + SW-cache clear after every
fresh VDH download (`patch_vdh`), warning if the sed patterns no longer
match a new upstream build. Manual re-patch only needed if that warning
fires.
2. Bumped `manifest.json` version (10.5.24.2 → 10.5.24.3).
3. **Cleared the service-worker script cache** — `Default/Service Worker` —
   from the session profile AND the template. THIS was the hidden one:
   chromium serves the cached (pre-patch) SW script even after the file
   changes AND the version bump, for `--load-extension` extensions. Clones
   inherit the template's cache, so every session kept running old code.
   After any future extension patch: bump version + delete
   `Default/Service Worker` in template + affected profiles (browser closed).

Verified: fresh profiles (Xvfb) and warm profiles open exactly ONE tab; VDH
service worker still loads.

## Launch flags: sandbox + infobar (debugged 2026-09-15)

Two warnings Chromium shows as a bar under the toolbar, and their fixes
(both in `pi/browser/playwright-config.json` + the server args registered by
`pi/extensions/browser-profiles.ts`):

1. `--no-sandbox`: Playwright defaults `chromiumSandbox: false`, and the MCP
   *forces* it false as a CLI-level override (merge order: defaults < config
   file < env < CLI, and the action handler pre-sets `sandbox: false` unless
   `--sandbox` is passed). So the config key alone never wins — you need
   `"chromiumSandbox": true` in launchOptions **and** `--sandbox` in the
   server args. Verified: no `--no-sandbox` on any process, real sandbox.
2. `--disable-blink-features=AutomationControlled`: the MCP hardcodes this
   anti-detection flag for chromium (skipped only if your args already
   contain some `--disable-blink-features` variant). Chromium's bad-flags
   infobar flags the switch regardless of value (empty value does NOT help);
   `--test-type` (chromedriver's official switch) suppresses the bar while
   keeping the stealth flag → `"--test-type"` in launchOptions args.

### Debugging traps that cost hours — check these first

- **The bar only appears on persistent contexts.** `chromium.launch()` +
  `newPage()` (incognito-style) never shows it — only `launchPersistentContext`
  (what the MCP uses) does. Reproduce with persistent contexts.
- **The VDH extension's welcome tab steals focus and never shows the bar**;
  infobars attach to the tab active at creation. Always `tabs select 0` (or
  `page.bringToFront()`) before judging presence.
- **Chromium shows one bad flag at a time** — fixing `--no-sandbox` reveals
  the *next* bad flag. After any flag change, re-check for a new bar.
- **dwm parks hidden-tag windows off-screen** (negative x, outside the
  xrandr bounding box) and without a compositor X cannot capture them —
  `maim`/`import` return solid garbage. For visual checks that must not touch
  the user's display, run the MCP server against a private `Xvfb :31` and
  `import -display :31 -window root` (worked well; `xvfb-run` also fine).
- **The MCP server config lives in `browser-profiles.ts`** — command/args/env
  edits take effect on the next session or `/reload` (which re-registers the
  server). In-session, `/mcp` → reconnect reuses the registered config. A
  killed server process reconnects automatically on the next call (unlike
  the old vendored adapter, which stayed dead until a manual reconnect).
- Verify flags via `tr '\0' '\n' < /proc/<pid>/cmdline` — use *substring*
  greps (`grep -o -- '--test-type[=]*'`); exact-line `-x` checks produced a
  false negative once (possibly an exec race).

## Seeded prefs: muted audio + no restore bubble

`pi/browser/preferences.json` is deep-merged into every fresh clone (`seedPrefs`)
and into every `mcp-chrome-*` profile by `apply-preferences.sh`. Besides the
download dir it seeds:

- `profile.default_content_setting_values.sound: 2` (BLOCK) — all sites muted
  by default; the user unmutes per-site in the window (omnibox speaker icon /
  player unmute button). Deliberately NOT `--mute-audio`: that flag mutes at the
  audio-manager level with no UI to undo it, and the point is that the human
  can unmute during manual interventions.
- `profile.exit_type: "AppExitedCleanly"` (+ `exited_cleanly: true`) — kills
  the "Restore Pages? Chromium didn't shut down correctly" bubble. Chromium
  writes `exit_type: "Crashed"` at startup and only flips it back on a clean
  exit, so any killed browser (template window, snapshot source) leaves it
  Crashed on disk; rsync faithfully propagates that. Re-seeding on every clone
  fixes it regardless of template state, and `browser-snapshot.sh` re-runs
  `apply-preferences.sh` on the template after each merge so the template
  stays clean too. The template's stale `Default/Sessions` (the restore
  payload) was removed; snapshot excludes keep it out going forward.

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
