Project Specifics:
* Linux only
* Use available skills to solve problems for the user.
* Verify edits to bash and shell scripts with `shellcheck`
* Use read-only command line tools to check your work, shellcheck, jq/yq etc.
* Use the web-browser-use skill to interact with specific websites

## pi config layout (this repo)
The global pi config directory is redirected into this repo via `PI_CODING_AGENT_DIR`. Do NOT assume `~/.pi/`.
  * `pi/` — GLOBAL pi config, shared across every project. Preferred location for user-wide changes: `pi/settings.json`, `pi/mcp.json`, `pi/APPEND_SYSTEM.md`, and the `pi/agents/`, `pi/skills/`, `pi/extensions/`, `pi/prompts/`, `pi/themes/`, `pi/snippets/`, `pi/scripts/` dirs. Edit here when asked for a "global" / "default" / "preferred" change.
  * `.pi/` — PROJECT-LOCAL pi config (this repo only): `.pi/skills/`, `.pi/APPEND_SYSTEM.md`, `.pi/settings.json`. Edit here when asked for a project-specific change.
  * Sessions are NOT stored here; they live at `~/.local/state/pi/sessions` (`PI_CODING_AGENT_SESSION_DIR`).

When the user references `@pi/...` they mean the global config above; `@.pi/...` means project-local.
