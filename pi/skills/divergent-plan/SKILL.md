---
name: divergent-plan
description: Use when the user asks for a divergent plan.
license: MIT
compatibility: any
---
Deep autonomous planning. The agent explores the whole solution space alone, deferring every non-obvious decision into a fork whose options are each fully explored, then spends the user's attention once: a single batched handoff where the user collapses the DAG into an implementation-ready linear plan via a series of questions.

The human has limited attention, sleeps, and runs several agents at once. The agent is single-purpose and can work a task essentially without limit — **if the task is fully specified and "done" is defined.** Divide planning accordingly: **the agent plans alone for as long as possible**, and the human's attention is spent **once, at the end, in one batch**.

A divergent plan is a **DAG of named nodes** in which every non-obvious decision is **deferred into a fork** — two or more options, each explored as far as if it had been chosen. Planning is complete when the only things left open are the calls only a human can make, and *any* combination of those calls yields a plan with nothing left to ask.

## Plan, don't do

Planning produces decisions, not deliverables. The pull to just start building is usually the signal that the map is done. Two sanctioned exceptions: **prototypes**, which answer questions and are thrown away, and **chores that unblock a decision** (provisioning, signing up) — do the ones you can; batch the human-only ones into the handoff as action items.

## Experiments

Most questions a plan waits on can be answered by running real code, not by asking. **Experiment before you fork:** test the actual thing and observe the result.

- **Worktree, not the main repo.** Unless the user says otherwise, all repo activity for the effort — experiments, prototypes, built variants for side-by-side windows — runs in a git worktree at `worktrees/<adjective_noun>/` in the project repo (same name as the plan), leaving the main checkout untouched.
- **Scratch lives in one place: `worktrees/<adjective_noun>/.scratch/`** (gitignored). A single-question one-off — a throwaway bash/python/ts script — is deleted once answered; an experiment worth keeping as evidence for the future ("x causes y because z") stays. Write it as if it could theoretically be copied into the repo and committed: the repo's language and patterns. Never anywhere else in the worktree.
- **Headless first.** CLI runs, script harnesses, headless drivers — the cheapest experiment that answers the question wins. GUIs are the hard case, not the norm.
- **Web UIs** — drive with the `web-browser-use` skill rather than hand-rolled automation.
- **Desktop GUIs (agent-facing)** — drive with `~/source/gui_automation`: the `ga` CLI sees (screenshots) and drives (key, type, click, drag) a real app inside a local QEMU VM, without touching the host display or input.
- **Consideration scales with the machine.** Gate all host-display behaviour on `$dotfile_tag`. `hackerman`/`pc` are the user's personal devices — pin every window the agent spawns with `DWM_FORCE_MONITOR=0 DWM_FORCE_TAG=8` (dwm reads these from the client's environment; export on the launcher so whole process trees inherit them), and never screenshot the host display: the user works concurrently, tag 8 isn't focused, and a host screenshot would capture their unrelated work. `snuggy` is a standalone server — nobody is watching, go wild.
- **User-facing windows (handoff)** — spawn the window as usual on the host display; on personal devices the only addition is the pinning env vars above.
- **Verify what you can't see.** Screenshots — `ga snap` in the VM, or on snuggy the host display too — go to an image subagent for vision tasks: layout, state, differences, "is the VFX effect rendering correctly", and similar. This flow runs regardless of the model's own capabilities; defer to the image subagent whenever the model lacks image comprehension.
- **The residue is taste.** Micro-interactions, game feel, UX feel — what an agent cannot judge — never gets asked mid-flight. It becomes a fork whose options are **side-by-side user-facing windows** with slightly different interaction semantics, pinned to tag 8 and labelled A, B, C… — arbitrarily many, soft cap around 8; two is just the common case since most choices are roughly binary. The user picks one at handoff and the fork collapses.

## The artifact

Generate a name with `alliterate_name.py` — a human-memorable handle (e.g. *Furious Fennec*) the user can refer to this effort by across sessions and agents. The plan lives at `~/.local/state/pi/divergent_plans/<adjective_noun>/PLAN.md`, updated **continuously as you go** — the document is the durable state, so a fresh session, this one ends, or a context window gets filled, resumes from it alone. Bulky evidence — research findings, prototype notes — goes in sibling files under `~/.local/state/pi/divergent_plans/<adjective_noun>/`; the plan gists and links, never pastes.

```markdown
# <Alliterative Name> — <one-line title>

## Destination   <!-- what done looks like once implemented; fixes scope -->
## Inputs        <!-- what was given/read, linked -->
## Settled       <!-- facts and assumptions resolved autonomously, one line each -->
## The DAG       <!-- ascii diagram of named nodes and forks -->
### <node>       <!-- what happens here + its done-check -->
### Fork f-<name> <!-- the question; each option explored to closure; recommendation -->
## Fog           <!-- in scope but not yet sharp enough to node or fork -->
## Out of scope  <!-- ruled out beyond the destination; never graduates -->
```

Every node carries a **done-check** — the computable test that the node is finished. That is how "done" is defined before implementation ever starts.

**Refer by name.** In everything the human reads, a node or fork is referred to by its name (`f-keybinds — hotkey dispatch scope`), never a bare id.

## Flow

### 1 · Intake — the only early interaction

The user braindumps what exists: requirements, specs, links, half-formed ideas. Read everything it points at. Ask **at most one round of questions, and only ones whose answers reshape the destination**. Everything else is either look-up-able (step 2 settles it), an assumption (record it under Settled as one), or a human value-call (it becomes a fork).

**"Done" must be fully defined before proceeding — non-negotiable.** Synthesise the braindump into a crisp statement of what done looks like (the Destination) and how it will be recognised (done-checks). Everything downstream rests on this: the agent can work autonomously without limit only on a task where "done" is defined; without it the whole autonomous phase is steering blind. If done cannot yet be stated, defining it *is* the first thing to resolve with the user.

If intake shows the whole thing is small — no fog, no forks, one linear pass — say so, write the linear plan directly, and skip the ceremony.

### 2 · Expand — work alone, for a long time

The default move is **never ask; explore.** Loop until a stop condition (below) fires:

- **Facts settle; decisions fork.** Any question answerable by looking — filesystem, code, docs, the web, an experiment — is answered, now, by you; record it under Settled. Only questions of human value (scope, taste, risk, effort, priority) become forks.
- **Experiment to settle facts.** Running real code beats speculating — see [Experiments](#experiments). Anything an experiment can answer must not become a fork or a question.
- **Forks close; they don't wait.** For each option, answer its follow-up questions *now*, recursively — explore every branch as if chosen, down to implementation-ready detail. **Closure test:** if the user picks exactly this option and nothing else, zero follow-up questions remain. A fork with an option that would still need its own interview is unfinished work.
- **Fire research off-thread.** Questions needing outside reading go to parallel background research subagents: primary sources only, findings written to a file, gist and link into Settled. Keep planning other branches while they read.
- **Prototype to raise fidelity.** When "how would it behave?" or "how would it look?" gates a branch, build a throwaway prototype — one command to run, no persistence, no polish, state visible. Judge it yourself where you can; where it's a matter of taste, the prototype's variants become fork options with the artifact as evidence.
- **Mind the fog.** What you can't yet phrase sharply as a node or fork goes under Fog — in scope, just not resolved enough. Graduate it as exploration sharpens it. What sits beyond the destination goes under Out of scope and never graduates; when a live node turns out to sit past the destination, close it with a one-line Out-of-scope entry.
- **Coin the language.** As terms crystallise, capture canonical vocabulary in the repo's `CONTEXT.md` (lazily, inline). Flag any fork that will deserve an ADR once collapsed — hard to reverse, surprising without context, a real trade-off; all three.

The user may interject at any time — they're running other agents. An interjection is input, not a stop; fold it in and keep going.

### 3 · Critique — machines before the human

Before spending human attention, spend machine attention: run a `review` subagent over the plan, then challenge its findings with `review-reflect`. Fold in what survives. For a large plan, repeat until a round produces no surviving findings.

### 4 · Handoff — one batch, then collapse

Summarise the plan in your context window, then put **every open fork to the user in a single `ask_user_question` call**: dependency order, each question's options are the fork's options, **recommendation listed first** with its one-line why. Mark conditional forks ("if f-x = A, f-y is moot") so a partial answer collapses cleanly. Include the human-only action items from step 2. Taste forks resolve side-by-side: leave their labelled option artifacts (A/B) running on tag 8, and make the pick one of the questions. The user may simply accept all recommendations.

Then **collapse**: rewrite the artifact in place as a **linear plan** — one path through the DAG. Each fork becomes a line in a decision log (chosen option + why; ADR-flagged forks get their ADR at implementation time). Nodes keep their done-checks. The result is implementation-ready: nothing left to decide, nothing left to ask.

## Stop conditions

Keep expanding until one fires:

- **The space is exhausted** — Fog empty, every fork option closed under the closure test, every node carrying a done-check. Proceed to critique and handoff unprompted.
- **The user says stop.** Go straight to handoff with the plan as it stands; forks whose options aren't fully closed are marked, with the gaps named.
