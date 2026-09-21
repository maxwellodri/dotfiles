Project Specifics:
* Linux only
* Use available skills to solve problems for the user.
* Verify edits to shell scripts with `shellcheck`
* Use read-only command line tools to check your work, shellcheck, jq/yq etc.
* Use the web-browser-use skill to interact with specific websites

## Comments
* Write self-documenting code with long variable/function names. Prefer this over comments.
  * Good: `function mergeXWithY(..)`
  * Bad: `// Merge X and Y` + `function merge(..)`
* Doc comments (TypeScript `/** ... */`, Python docstrings, Rust `///`) are for external / pub-facing surface. Regular comments sparingly, and only for internal implementation details.
* In bash scripts, a `help()` function wired to `--help` is the pub-facing documentation — more useful than a comment block.
* Comments explain the `why` (invariants, constraints, non-obvious decisions), never the `what`. Be terse. Exception: name-dropping the algorithm in use, e.g. `// forward Euler integration` — a named algorithm is not a `what`.
* Comments must be path-independent: written for a reader with no knowledge of how the code came to be. They reflect the current state of the code, never the past; the only forward-looking form is a `// TODO: ...` prefix — the one greppable, canonical marker for deferred work.
  * Past: never reference history — fixed bugs, past behavior, past workarounds, PR numbers, where code was copied from. Once the bug is fixed, that context is noise; state the standing invariant instead.
  * Future: referencing PR numbers, workarounds, removals, upstream fixes etc. is fine — but the comment must be prepended with `// TODO:`.
  * Good: `// forward Euler diverges once dt > H/V_t, clamp sub-step dt`
  * Bad: `// fixes bug where fast-forward invented mass on big dt`
* Leave any user-written comments untouched.

## pi config layout (this repo)
The user already knows the layout of this repo — this note is a quick reference for you so you pick the right path:
  * `PI_CODING_AGENT_DIR` redirects the global pi config dir into this repo. Do NOT assume `~/.pi/`.
  * `pi/` — GLOBAL config (every project): `settings.json`, `mcp.json`, `APPEND_SYSTEM.md`, plus `agents/`, `skills/`, `extensions/`, `prompts/`, `themes/`, `snippets/`, `scripts/`.
  * `.pi/` — PROJECT-LOCAL config (this repo only).
  * Sessions are NOT stored here; they live at `~/.local/state/pi/sessions` (`PI_CODING_AGENT_SESSION_DIR`).
  * `@pi/...` → global config; `@.pi/...` → project-local.
