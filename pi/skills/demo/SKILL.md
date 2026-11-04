---
name: demo
description: Use whenever the user asks for a demo, or a fork, node, or handoff hinges on something the user must see to judge (layout, interaction, sequencing, feel, UI/UX).
license: MIT
compatibility: any
---
# Demo
The purpose of the demo is for the user to answer  questions and close forks in a plan. Create a slide deck as a single page html document. The document is an interactive rendering of the decision tree (such as an ask-user-question batch, or a feature walkthrough: generalising to anything the user must *see* to judge. Demos are disposable by design; all files live in one directory, and is thrown away once decisions land.

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
- Continuous answers, e.g. consider rendering a water simulation: sliders of parameters, within a single deck slide is more appropriate.

## Verify (gui-automation skill — there is no host chromium)
Boot the VM, open the deck in its browser, screenshot every distinct state, read each via the `image_reader` subagent (give the agent the html fragment and the screenshot); fix and re-shoot. `node --check` the script body. Never hand off to the user unverified.

## Handoff
Open in Firefox, if applicable you'll want to call the ask_user_question tool right after opening in Firefox.
```sh
DWM_FORCE_TAG=8 DWM_FORCE_MONITOR=0 firefox <dir>/demo.html
```
