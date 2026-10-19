---
name: analyze-sessions
description: Mine past pi sessions for recurring user responses and turn them into $-snippets, and prune unused ones; also transcript search, session replay, and token-usage rollups.
disable-model-invocation: true
---

# Analyze Sessions

Query past pi sessions (JSONL under `$PI_CODING_AGENT_SESSION_DIR`, default
`~/.local/state/pi/sessions`). Scripts are stdlib Python 3 in
[scripts/](scripts/) — run with `python3` from anywhere, read-only.

Ported from amosblomqvist/pi-config `skills/analyze-sessions`, with the
sessions path adapted to this machine and the workflow re-aimed at snippet
mining. Each session is a JSONL file: `session` header (`cwd`, `id`),
`model_change`, `thinking_level_change`, and `message` records (roles
`user` / `assistant` / `toolResult`); assistant messages carry `usage.cost`
already split into input/output/cacheRead/cacheWrite/total.

## Persistent memory between runs

`~/source/private/runtime/pi/analyze_sessions_notes.md` carries findings
across runs: snippets created/edited/retired, rejected candidates and why, and
method notes. Read it before proposing — a recorded rejection stands unless
usage has clearly changed. After the user has answered this run's proposals,
append a `## Run <date>` section with the verdicts (fill in any PENDING
entries). Never delete old sections — the history is the trend signal.

## The main event: recurring responses → new snippets

The biggest win this skill offers: text the user types over and over means
the environment is missing something — usually a snippet, sometimes standing
steering or automation. Find it, triage the fix, check it isn't covered,
propose it.

### 1. Dump prompts

```bash
python3 scripts/prompts.py --since 30d --max-chars 1500
```

Output is markdown grouped by project. Wider windows (`90d`, `--until` to
bound an era) give a stronger frequency signal; the char cap keeps pasted
context out.

### 2. Start where it hurt

Corrections cluster around struggle; a smooth session has little to teach.
Narrow the dump to sessions with failed tool calls, then drill into the
worst:

```bash
python3 scripts/prompts.py --since 30d --errors-only
python3 scripts/cost.py --since 30d --by session --errors-only --limit 10
python3 scripts/show_session.py --session <id>   # bare filters render the newest match
```

The `show_session.py` header carries duration, message counts, and error
count — high errors plus long duration is the profile worth mining.

### 3. Spot recurring responses

Look for **user-authored text that repeats across sessions, ideally across
projects** — the frequency across independent sessions is the signal. The
fruitful shapes:

- **Steering & corrections** — the same nudge re-sent ("verify with
  shellcheck", "don't commit, I'll review"): each repetition is a session
  where the right fix — snippet, steering, or hook (step 4) — would have
  saved a round-trip
- **Standing context** — the same setup paragraph re-typed (environment
  notes, preferences, constraints that apply most sessions)
- **Standard replies** — the same canned answer to recurring agent
  questions (approvals, dispositions)

Not candidates: one-off asks, pasted blobs, anything with project-specific
paths or names that won't generalize to other repos.

Expansions never pollute this signal: `$name` and `@path` expansions are
logged as separate `custom_message` records (`customType:
"promptExpansion.injected"`), never as user prompts — anything recurring in
`prompts.py` output was genuinely typed. The same marker doubles as a
snippet usage counter (step 7).

Once a candidate phrase is spotted, quantify it — exact repeats are
greppable:

```bash
python3 scripts/search.py "verify with shellcheck" --in user --since 90d
```

Hits across several sessions (not several hits in one session) are the
good ones.

### 4. Triage the fix — not every recurrence is a snippet

A snippet only works when the user remembers to type `$name`; a repeated
response may point at a fix that doesn't depend on the user at all. Classify
each candidate:

| Recurrence shape | Fix |
| --- | --- |
| Should apply in (nearly) every session | Steering — `pi/APPEND_SYSTEM.md` (global) or the repo's `AGENTS.md` |
| Tied to a task type or whole workflow | A skill |
| Mechanically checkable; the agent should never get it wrong | An extension or hook — prose can't fail a build |
| The user's in-the-moment call, each time | Snippet — continue below |

### 5. Filter against existing snippets

List `$PI_CODING_AGENT_DIR/snippets/` (`pi/snippets/` in the dotfiles
repo). Layout: `<name>.md` or `<name>/snippet.md`. **Read the bodies**, not
just the names — a candidate is covered if an existing snippet already
expresses it, even in different words. If one is *almost* right, propose an
edit to it instead of a new near-duplicate.

The run-notes file (see *Persistent memory between runs*) records the
snippet inventory as of the last run; the directory listing is always
authoritative.

### 6. Propose up to 5, then wait

Each proposal: `name` (`[a-zA-Z0-9_-]+`, short, reads as a word — users
type `$name`), `body` (the reusable text — its **first line doubles as the
autocomplete description**, keep it a clear one-liner), and the evidence
(which sessions/projects it recurred in), ordered strongest-first by
distinct-session count. A good snippet is a fragment,
not a document; generic across projects; something the user would actually
bother typing `$name` for.

Create files in `pi/snippets/<name>.md` **only after the user approves**.
Snippets go live in autocomplete within ~2 s (mtime/TTL caches in
snippet_expansion.ts), no reload needed. Then record the run's verdicts in
the run-notes file (see *Persistent memory between runs*).

### 7. Retire unused snippets (run occasionally)

Snippet usage is directly countable: every `$name` expansion is logged with
the snippet's path via the `promptExpansion.injected` marker (`@path`
includes use the same marker — filter to `/snippets/`):

```bash
SESS="${PI_CODING_AGENT_SESSION_DIR:-$HOME/.local/state/pi/sessions}"
for f in $(rg -l promptExpansion.injected "$SESS" -g '*.jsonl'); do
  rg promptExpansion.injected "$f" | jq -r '.details.files[]?.path // empty' 2>/dev/null
done | grep '/snippets/' | sort | uniq -c | sort -rn
```

Snippets with zero hits over the window are retire candidates. Don't gauge
usage by grepping snippet body text — assistant thinking quotes bodies and
inflates counts. Propose retirement like any other change (delete only
after approval) and record the verdict in the run-notes.

## Scripts

Shared filters on all four: `--since/--until WHEN` (`7d`, `2w`, `3h`,
`30m`, ISO date/datetime), `--cwd SUBSTR` (repeatable), `--model SUBSTR`,
`--session ID` (8-char prefix ok), `--limit N`, `--min-messages N`,
`--grep SUBSTR`, and more. Subagents are excluded by default in
everything except `cost.py` (a subagent's "user" message is an
agent-authored task, not your prompt).

### `prompts.py` — dump user prompts (primary tool)

Markdown grouped by project, newest first; `--format jsonl` available.
Prompts over `--max-chars` (default 2000) are dropped — they're pasted
context, not prompting.

```bash
python3 scripts/prompts.py --since 30d --max-chars 1500
python3 scripts/prompts.py --cwd /home/maxwell/source/dotfiles --since 60d
```

### `search.py` — search across transcripts

Substring by default, `--regex` (smart-case). `--in user|assistant|both`
(default both), `--context N` lines around matches. Hits print the session
header plus a `show_session.py --session <id>` drill-in line.

```bash
python3 scripts/search.py "shellcheck" --in user --since 60d
python3 scripts/search.py --regex "TODO\\(.+\\)"
```

### `show_session.py` — render one session as markdown

`--latest`, `--session <id/prefix>`, or filters + newest match. Truncates
tool output (2000), assistant text (4000), thinking (600) — `0` disables,
`--max-thinking -1` omits thinking. `--include-subagents-content` appends
nested subagent transcripts.

```bash
python3 scripts/show_session.py --latest
python3 scripts/show_session.py --session 019e475b
```

### `cost.py` — token-usage rollups (minor)

Present because it's occasionally a convenient proxy for *token usage* —
the plan here is a subscription, so the dollar figures are not real spend
and rate limits aren't a concern. Ignore the money; read the token columns
if you ever need "which project/model eats the most context".

```bash
python3 scripts/cost.py --since 30d --by project
python3 scripts/cost.py --by model        # context usage per model
```

## Notes

- All paths read-only; scripts never modify session files.
- `scripts/sessions.py` is a reusable library — import it for ad-hoc analysis.
- Full scan over ~200 sessions: ~1–2 s, no caching.
