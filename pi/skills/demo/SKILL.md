---
name: demo
description: Use whenever the user asks for a demo, or a fork, node, or handoff hinges on something the user must see to judge (layout, interaction, sequencing, feel, UI/UX).
license: MIT
compatibility: any
---
# Demo

A slide deck in a browser: an interactive rendering of a decision tree, an ask-user-question batch, or a feature walkthrough — anything the user must *see* to judge. Disposable: one directory, thrown away once decisions land.

## Location
Divergent-plan worktree → `.scratch/`. Elsewhere → `/tmp/pi/<name>/`. Screenshots and other assets live in the same directory (external images are fine).

## Build
1. Copy [deck.css](deck.css) into the page's `<style>`, then tweak. Structure per [examples/async-questions.html](examples/async-questions.html): header, `.slide`s, ◀/▶/dots/counter, keys ←/→ n/p.
2. Mocks are styled HTML, never canvas. Verbatim strings from the real system.
3. State changes are real DOM swaps plus CSS keyframes (cursor blink, spinner); char-drip streaming for "still working" beats.

## Questions ↔ slides
- One ask_user_question per slide; ask the questions in pi in **deck order**.
- A question slide carries a **Question N** badge — bold, on a background colour used nowhere else in the deck.
- Discrete answers → top-bar **buttons** (not radios/checkboxes) that switch the mock between the precanned answers; the slide argues each trade-off.
- Combinatorial answers (theme + widget set + …) → no per-answer sublevels: one clickable toggle per element, the user composes.

## Verify (gui-automation skill — there is no host chromium)
Boot the VM, open the deck in its browser, screenshot every distinct state, read each via the `image_reader` subagent; fix and re-shoot. `node --check` the script body. Never hand off unverified.

## Handoff
```sh
pgrep -x firefox >/dev/null && firefox <dir>/demo.html || echo <dir>/demo.html
```
Only spawn firefox yourself pinned: `DWM_FORCE_TAG=8 DWM_FORCE_MONITOR=0`.
