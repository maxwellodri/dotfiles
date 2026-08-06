Project Specifics:
* Linux only
* Use available skills to solve problems for the user.
* Verify edits to shell scripts with `shellcheck`
* Use read-only command line tools to check your work, shellcheck, jq/yq etc.
* Use the web-browser-use skill to interact with specific websites

## pi config layout (this repo)
The user already knows the layout of this repo — this note is a quick reference for you so you pick the right path:
  * `PI_CODING_AGENT_DIR` redirects the global pi config dir into this repo. Do NOT assume `~/.pi/`.
  * `pi/` — GLOBAL config (every project): `settings.json`, `mcp.json`, `APPEND_SYSTEM.md`, plus `agents/`, `skills/`, `extensions/`, `prompts/`, `themes/`, `snippets/`, `scripts/`.
  * `.pi/` — PROJECT-LOCAL config (this repo only).
  * Sessions are NOT stored here; they live at `~/.local/state/pi/sessions` (`PI_CODING_AGENT_SESSION_DIR`).
  * `@pi/...` → global config; `@.pi/...` → project-local.
