---
name: demo
description: Use whenever the user asks for a demo, or a fork, node, or handoff hinges on something the user must see to judge (layout, interaction, sequencing, feel, UI/UX).
license: MIT
compatibility: any
---
# Demo
The purpose of the demo is for the user to answer questions and close forks in a plan.
Two kinds of demo:
* A slide deck is a single page html document. The document is an interactive rendering of the decision tree (such as an ask-user-question batch, or a feature walkthrough: generalising to anything the user must *see* to judge). Demos are disposable by design; all files live in one directory, and are thrown away once decisions land. Always use this, when there isn't an existing gui to modify, or to "sell" your idea to the user before implementation. Imagine them as a senior/manager, and you're a junior trying to get your feature merged. So you mock it up in a web demo/slide deck.
* A fork demo differs in that it is real code tied to an existing implementation/codebase. It's a throwaway branch/worktree of an existing program, often a GUI (or TUI), rigged into a short playable slice/demo. One important thing is that you must not impact existing code (in the main branch). This can be achieved via e.g. a worktree to host your changes, and for example, environment variables for a client/server (e.g. tmux) to have the server watch/write to a non-standard path. The fork hacks out any part of the program that gets in the way of the user quickly testing the demo. For a game, this would include modifying the menu flow to load a demo level (and skip the main menu for example) that highlights an introduced game mechanic in a game. When merging you'd then only merge the game mechanic code, not the adjusted/skipped menu flow. Use when the questions are about the real thing.

## Location
For slide deck:
  * Divergent-plan worktree → `.scratch/`. Elsewhere → `/tmp/pi/<name>/`. Screenshots and other assets live in the same directory (external images are fine).
For fork:
  * New worktree under `worktrees/`. If part of `divergent-plan`, reusing existing worktree is fine. Ensure the existing program continues unmodified, and e.g. you make your modified program use different paths for its sockets/different ports etc.

## Build (slide deck)
1. Copy [deck.css](deck.css) into the page's `<style>`, then tweak. Structure per [examples/async-questions.html](examples/async-questions.html): header, `.slide`s, ◀/▶/dots/counter, keys ←/→ n/p.
2. Mocks are styled HTML, never canvas. Verbatim strings from the real system.
3. State changes are real DOM swaps plus CSS keyframes (cursor blink, spinner); char-drip streaming for "still working" beats.
## Build (fork demo)
1. Spin up a worktree in `worktrees/`.
2. Make the changes, split into logical commits, ensure there is a clear commit-level separation between throwaway harness changes to make the demo work, and changes you actually intend to upstream. For ease of review, make the upstream-bound changes first, then the harness-level hacks on top.
3. Verify it yourself with the `gui-automation` skill.
4. Verify it by giving it to a subagent and have them perform the same steps as you; they use `gui-automation` as well.
5. Hand off to the user for testing. For gui programs, spawn with env vars:
`DWM_FORCE_TAG=8 DWM_FORCE_MONITOR=0 <program>`
For TUI programs (the terminal persists in zsh after the TUI exits; `--always-new-process` skips the wezterm daemon so the env vars reach the window — same as sxhkdrc super+Return; `--cwd` optionally sets the shell's working dir):
```
DWM_FORCE_TAG=8 DWM_FORCE_MONITOR=0 wezterm start --always-new-process --cwd <dir> -e zsh -c '<TUI program>; exec zsh'
```
6. Give the user the list of commits (short hash) that are intended to be upstreamed (and range). E.g.:
A,B,C <list of commits>
A..C <range>
This is so the user can cherry-pick and review specific commits themselves; and if they have no feedback and the code is good to merge, they already have everything they need without asking.
7. If the user has feedback however, continue to iterate, based on the user's feedback, redoing prior steps as necessary, then repeat steps 5 and 6. Depending on the nature of the work, the user may give you the go ahead to land the changes upstream (always update main first — pull in anything landed since the worktree forked — then rebase the worktree commits onto main). Or they'll cherry-pick the commits themselves.


## Questions ↔ slides
- One ask_user_question tool call, one question per slide; ask the questions in pi in **deck order**. For fork demos, ask them in the order the user will interact with them, if applicable. But always present a final "general feedback" question (always the last question) for fork demos, where the user will give any general feedback/feedback that doesn't cleanly map to a question.
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
