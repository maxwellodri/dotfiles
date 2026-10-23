---
name: divergent-plan
description: Use when the user asks for a divergent plan.
license: MIT
compatibility: any
---
Deep autonomous planning. The agent explores the whole solution space alone, deferring every non-obvious decision into a fork whose options are each fully explored, then spends the user's attention once: a single batched handoff where the user collapses the DAG into an implementation-ready linear plan via a series of questions. Implementation can then follow.

A broad goal of this skill is to **minimise human attention**. The human has limited attention, sleeps, and runs several agents at once. The agent is single-purpose and can work a task essentially without limit **if the task is fully specified and "done" is defined.** Divide planning accordingly: **the agent plans alone for as long as possible**, and the human's attention is spent **once, at the end, in one batch**, then implementation, then the human spends attention to review/nit etc.

A divergent plan is a **DAG of named nodes** in which every non-obvious decision is **deferred into a fork** — two or more options, each explored as far as if it had been chosen. Planning is complete when the only things left open are the calls only a human can make, and *any* combination of those calls yields a plan with nothing left to ask.

## Plan and resolve forks
Planning produces deliverables: decisions, prototypes, experiments, not production code. The pull to just start building is usually the signal that the map is done. Some forks in the divergent plan can be answered on your own; see below.
Unless the user says otherwise, do everything in a git worktree at `worktrees/<adjective_noun_{1-3 word description of the work, e.g. snuggly_snail_scene_edit, bad_badger_nvim_rust_analyzer}>/`, define this as the <worktree name> henceforth in the project repo (same name as the plan), leaving the main checkout untouched.
Generate the adjective and noun pair via `qz generate-name`.
Once coined retitle this session via the `name_session` tool as `Adjective Noun: <short description>`.
The short description can be longer than the 1-3 word description used in the worktree name; soft cap of ~5-8 words.
Both descriptions, the worktree and the session title, name the work, not the plan, e.g. `Furious Fennec: portal renderer`
- Prototypes let the user answer questions and are thrown away. These are a deliverable produced at handoff time, they are better than directly asking questions when it comes to matters of taste/personal preference, e.g. layout of a GUI. To produce these, use the gui-automation skill, first to test them internally, then at handoff provide a split, e.g. several variations of the prototype and the user picks. Make sure to draw attention to the prototype via one of your batched questions e.g. A or B.
- Chores unblock a decision (provisioning, signing up, updating depeendencies). Do the ones you can then batch the human-only ones into the handoff.
- Experiments answer questions a plan waits on and can be answered by running real code, not by asking. **Experiment before you fork:** test the actual thing and observe the result. The cheapest experiments go first: CLI, anything headless. GUIs are more complicated.
  - **Web UIs** — drive with the `web-browser-use` skill.
  - **Desktop GUIs** — Two types: agent facing, such as to iterate and check whether a GUI is "done". An agent can get 90% of the way there by self-checking the GUI themselves. Secondly, spawning the GUI to handoff to the user to inspect/give feedback. Drive both with the `gui-automation` skill.
  - Phone Apps - ask the user to provide an (Android) phone with USB debugging capabilities ; test in the UI in a loop via installing over ADB -> launching the App -> manually test the feature/functionality/take a screenshot
  - **The residue is taste.** Micro-interactions, game feel, UX feel; things an agent cannot judge. Don't ask mid-flight. Instead, it becomes a fork whose options are **side-by-side user-facing windows** (see `gui-automation`) with slightly different interaction semantics, labelled A, B, C… — arbitrarily many, soft cap around 8; two is just the common case since most choices are roughly binary. The user picks one at handoff and the fork collapses.
  - Some things cannot be answered, for example micro-interactions, game feel, ux feel; things an agent cannot judge should become a fork in the plan. Side-by-side user-facing windows at handoff for the user to judge (see `gui-automation`) are the gold standard. Soft cap of ~5 choices per fork but 2 is the most common case (binary choice). The user picks at handoff (via a question) and by evaluating the deliverable.
- Prior art is invaluable, use the `web_search` tool, `gh` CLI, the `scout` skill for speciic repos, and the browser-use skill for complex web tasks. Prior art search investigates if a similar problem has already been solved, and if so how, what learnings are applicable? Can we just reuse their answer, take it on as a dependency or rewrite but drawing heavy inspiration? Or is it an example of what not to do? You should **always** investigate prior art unless there is a good reason not to.
- Scratch work, any temporary files, e.g. one off scripts for an experiment (exception is the `scout` skill usage which follows that skill's guidance), use `worktrees/<worktree_name>/.scratch/`, which is gitignored. Prefer python, bash or typescript for scripts.
The plan itself gets written to `worktrees/<worktree_name>/.scratch/PLAN.md`, updated continuously as you go, treat the document as durable state, so compaction runs dont clear.

```markdown
# <Alliterative Name>: <one-line title>

## Destination   <!-- what done looks like once implemented; fixes scope -->
## Inputs        <!-- what was given/read, linked -->
## Settled       <!-- facts and assumptions resolved autonomously, one line each -->
## The DAG       <!-- ascii diagram of named nodes and forks -->
### <node>       <!-- what happens here + its done-check -->
### Decision decision-<name> <!-- the question; each option explored to closure; recommendation -->
## Fog           <!-- in scope but not yet sharp enough to node or fork -->
## Out of scope  <!-- ruled out beyond the destination; never graduates -->
```

Every node carries a **done-check** — the computable test that the node is finished. That is how "done" is defined before implementation ever starts.
**Refer by name.** In everything the human reads, a node or fork is referred to by its name (`decision-keybinds — hotkey dispatch scope`), never a bare id.

## Flow
### 1 · Intake — the only early interaction
The user braindumps what exists: requirements, specs, links, half-formed ideas. Read everything it points at. Ask **at most one round of questions, and only ones whose answers reshape the destination**. Everything else is either look-up-able (step 2 settles it), an assumption (record it under Settled as one), or a human value-call (it becomes a fork).

**"Done" must be fully defined before proceeding, this is non-negotiable.** Synthesise the braindump into a crisp statement of what done looks like (the Destination) and how it will be recognised (done-checks). Everything downstream rests on this: the agent can work autonomously without limit only on a task where "done" is defined; without it the whole autonomous phase is steering blind. If done cannot yet be stated, defining it *is* the first thing to resolve with the user.

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

### 4 · Handoff as one batch of questions then collapse

Summarise the plan in your context window, then put **every open fork to the user in a single `ask_user_question` call**: dependency order, each question's options are the fork's options, **recommendation listed first** with its one-line why. Mark conditional forks ("if decision-x = A, decision-y is moot") so a partial answer collapses cleanly. Include the human-only action items from step 2. Taste forks resolve side-by-side: leave their labelled option artifacts (A/B) running on tag 8, and make the pick one of the questions. The user may simply accept all recommendations.

Then **collapse**: rewrite the artifact in place as a **linear plan** — one path through the DAG. Each fork becomes a line in a decision log (chosen option + why; ADR-flagged forks get their ADR at implementation time). Nodes keep their done-checks. The result is implementation-ready: nothing left to decide, nothing left to ask.

## Stop conditions

Keep expanding until one fires:

- **The space is exhausted** — Fog empty, every fork option closed under the closure test, every node carrying a done-check. Proceed to critique and handoff unprompted.
- **The user says stop.** Go straight to handoff with the plan as it stands; forks whose options aren't fully closed are marked, with the gaps named.


## Implementation.
Only proceed once the user has approved the plan. Given the prior plan, implementation should be straightforward.

Small logical commits are imperative for the human to easily review. Keep commits small but numerous, the user can interactively rebase them into a smaller number later. A good rule of thumb is 200-400 LOC OR 2-3 changed files (whichever comes first) for behavioural changes. Renames/lockfile/refactorings churn etc are exempt from the prior numerical counts. A good sniff test is that you can describe in a single sentence without “and”. Tests with the code they cover, in the same commit. High level integration tests that test across multiple commits worth of work go in a separate commit.

Kernel style commit messages, under ~100 chars, as "<topic>: <short description>", refer to prior commit messages if available for a style guide.

## Post-implementation
Before handoff back to the user, rerun a review subagent then challenge its findings with `review-reflect`, and for a large block of work repeat until a round produces no surviving findings.

