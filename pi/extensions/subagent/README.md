# subagent

Delegate tasks to specialized subagents that run as isolated `pi` child
processes. Adapted from the official pi example at
`packages/coding-agent/examples/extensions/subagent/` (earendil-works/pi).

## Modes

- **single** — `{ agent, task }`
- **parallel** — `{ tasks: [{ agent, task }, ...] }`, up to 4 concurrent (8 max)
- **chain** — `{ chain: [{ agent, task: "... {previous} ..." }, ...] }`,
  sequential; each step's output is substituted into the next step's `{previous}`

Each child runs headless: `--mode json -p --no-session --no-extensions`, with
`--tools`, `--model`, and `--append-system-prompt` taken from the agent
definition. Output streams back live (tool calls, final text, per-agent usage).

## Agents

Agent definitions are Markdown files with YAML frontmatter:

| Scope | Location | Notes |
|-------|----------|-------|
| user | `pi/agents/*.md` | global, loaded for every project |
| project | `<cwd>/.pi/agents/*.md` | repo-controlled; prompted before running (set `confirmProjectAgents: false` to skip) |

Frontmatter fields: `name`, `description`, `tools` (comma-separated allowlist),
`model` (optional; omit to inherit the session default). The body becomes the
agent's appended system prompt.

Ships with two agents:

- `explore` — read-only recon (`read, grep, find, ls, bash`; bash used for
  read-only lookups only). Returns compressed, structured findings for the
  parent. Fan this out in parallel at the start of a task to map a codebase
  before planning.
- `general` — general-purpose worker with the full default tool set
  (read, write, edit, bash, …). Use it to execute independent, self-contained
  units of real work in parallel or in a chain, with an isolated context.
  Inspired by opencode's `general` subagent.

Add more agents (e.g. `reviewer`, `planner`) by dropping `.md` files into
`pi/agents/`.

### System-prompt injection

The extension injects the discovered agent list into the parent's system prompt
each turn (via a `before_agent_start` handler), so the parent LLM can pick the
right agent without reading `pi/agents/` itself. Both user and project agents
are listed; project agents are tagged `[project]`. Recomputed per turn, so edits
take effect immediately. Appended at the end of the prompt to preserve the
upstream prefix cache; never fires inside a subagent (children run with
`--no-extensions`).

## Two deliberate deviations from upstream

1. **Real binary, not the wrapper.** `pi` on PATH here is the user's wrapper
   (`~/bin/pi -> scripts/pi`), which paints a gruvbox canvas, re-reads the API
   key from `pass`, and sets a session dir — pointless overhead (and OSC
   theming noise) for a headless JSON-mode child. `getPiInvocation` re-invokes
   the real binary via `process.argv[1]` (the wrapper always launches it
   directly) and never falls back to PATH `pi`.

2. **`--no-extensions` on every child.** Children don't need herald,
   footer, theming, etc. The child's behaviour is fully pinned by `--tools`,
   `--model`, and `--append-system-prompt`.

Also fixed an upstream latent bug in `formatToolCall`'s `read` case
(`theme.fg` → `themeFg`, which would otherwise throw on any read with
offset/limit).

## Loading

Auto-discovered from `extensions/subagent/index.ts` — no `settings.json` change
needed. Edit and run `/reload` to pick up changes. Agent `.md` files are read
per-invocation, so editing `pi/agents/*.md` takes effect immediately.
