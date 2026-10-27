---
name: demo
description: "Build single-file HTML demo decks — gruvbox slide walkthroughs of a UI, flow, or feature with live state toggles, self-checked before handoff. Use whenever the user asks for a demo."
license: MIT
compatibility: any
---
# Demo

A demo is a **single-page, single-file HTML document** that lets the user *see and poke* a UI, a
flow, or a graphical feature — instead of reading a description of it. Slides carry the narrative;
interactive toggles let the user flip between states (fork options, variants, modes) live; mocked
windows replay the behavior. Disposable by design: one file, opened directly in a browser.

## Non-negotiables

1. **One file.** Everything inlined: styles, JS, content. The only externals allowed are CDN
   `<script>` libraries when hand-rolling would be worse (e.g. Mermaid for diagrams). Inline the
   full contents of [deck.css](deck.css) into `<style>` — drop classes the demo doesn't use, add
   demo-specific ones after it.
2. **Gruvbox dark**, per deck.css. Deviate only if the user asks.
3. **Interactive, not static.** Any choice the user is meant to judge (layout, wording, semantics)
   becomes an in-deck toggle that swaps real DOM state — never two adjacent screenshots. Controls
   bar with labelled buttons (`button.on` = active) + keyboard shortcuts when a slide has ≤3
   options (hint them in a `.dimnote`).
4. **Self-checked before handoff.** Screenshot every distinct state headlessly and verify via the
   `image_reader` subagent; fix and re-shoot until the reads match intent. Never hand off unverified.
5. **Animate state, don't fake it.** Streaming/typing effects are real JS (`setInterval` char-drip
   into a mock line); spinners/cursors are CSS keyframes (`.spinner::after`, `.cursor`). Replays
   get a `↻ replay` button.

## Structure

Deck chrome (copy from [examples/async-questions.html](examples/async-questions.html), the
reference implementation):

- `<header>`: title + one-line subtitle + optional status badge.
- `.deck > section.slide` per beat; exactly one `.active`; nav bar with ◀/▶ buttons, one dot per
  slide, `n / total` counter. Keys: ←/→ or n/p; per-slide option keys (1/2/3…) where offered.
- Slide kinds that work well: **title** (statement + bullets), **verdict** (`.verd` callout box:
  what's settled), **terminal mock** (below), **split** (two mocks side by side, `.cap` captions —
  e.g. before/after, t+0/t+N), **fork** (`.forktag` + controls bar + live mock), **recap**
  (decision list with `.recbadge` recommendations).

Terminal/UI mocks are styled HTML, **not** canvas (canvas is for plots/simulations only):

- `.term` window: chrome bar with three `.dot`s, `.body` = `.tscroll` (transcript) + `.board`
  (status rows) + `.rule` + `.editor` (with `.cursor`) + `.pfoot` (footer stats).
- Transcript line classes: `.m.user` (`>` prefix), `.m.asst`, `.m.toolcall`, `.m.toolres`
  (green left bar), `.m.notify`, `.m.quote`, `.m.followup`, `.m.abort`. Popup card: `.popup` with
  `.q`/`.d`/`.cust`/`.opt`/`.hints`.
- Mock fidelity rule: verbatim strings from the real system wherever they exist — the demo's job
  is to represent, not paraphrase.

## Workflow

1. Draft the slide list first (one line per slide: kind + what it shows + which states toggle).
2. Build the file; inline deck.css; write the JS (nav + toggles + animations) at the bottom.
3. Self-check: `timeout 60 chromium --headless --disable-gpu --no-sandbox --screenshot=/tmp/<state>.png --window-size=1280,860 file://$PWD/<demo>.html`, then read each shot with the `image_reader` subagent against what the slide should show. For toggle states not reachable without input, gate them on `location.hash` (e.g. `#style=B`) so headless shots can reach them.
4. Verify JS syntactically too: extract the `<script>` body to a temp file and `node --check` it.
5. Handoff: open pinned to tag 8 — `DWM_FORCE_MONITOR=0 DWM_FORCE_TAG=8 nohup firefox <file> >/dev/null 2>&1 &` — and point the user at it. Never screenshot the host display; headless shots only.

## Done when

- [ ] Opens standalone (no local file deps) in a browser.
- [ ] Every slide reachable via nav + keys; counter and dots agree.
- [ ] Every interactive control flips state live; headless screenshots of each state read back correct via `image_reader`.
- [ ] `<script>` body passes `node --check`.
- [ ] Opened pinned to tag 8 for the user.
