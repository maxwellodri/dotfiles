---
name: divergent-plan
description: Use as the default workflow when the user presents a non-trivial coding task.
license: MIT
compatibility: any
---
Deep autonomous planning. The agent explores the whole solution space alone, deferring every non-obvious decision into a fork whose options are each fully explored, then spends the user's attention once: a single batched handoff where the user collapses the DAG into an implementation-ready linear plan via a series of questions. Implementation can then follow.

Special instructions are included inline for game-development/mykaelium. These can be ignored if not working on that project/game-development-adjacent work.

A broad goal of this skill is to **minimise human attention**. The human has limited attention, sleeps, and runs several agents at once. The agent is single-purpose and can work a task essentially without limit **if the task is fully specified and "done" is defined.** Divide planning accordingly: **the agent plans alone for as long as possible**, and the human's attention is spent **once, at the end of planning, in one batch**, then implementation, then the human spends attention to review/nit etc.

A divergent plan is a **DAG of named nodes** in which every non-obvious decision is **deferred into a fork** — two or more options, each explored as far as if it had been chosen. Planning is complete when the only things left open are the calls only a human can make, and *any* combination of those calls yields a plan with nothing left to ask.

**Evidence** is a core concept throughout the skill. It is a deliverable that is not code (that gets upstreamed): bash command outputs, throwaway scripts/tests, CI outputs, subagent reviews, and human feedback from demos/proposals etc. Some evidence, such as CI output, the human doesn't need to see, it exists solely for the agent to confirm their code/implementation/planning is correct. Artifacts become evidence as they resolve: CI output when green, a demo when the user gives the green light, an uncollapsed DAG plan when a human gives signoff and collapses it. Human feedback is important, but treat it as budget-limited: other evidence should answer questions, reduce fog and collapse forks wherever possible. Human feedback is absolutely necessary at two points: plan handoff and post-implementation (demo signoff loops live inside these windows). By comparison, other evidence is cheap.

## Plan and resolve forks
Deliverables are split into roughly 3 kinds: evidence the human doesn't need to care about (CI, subagent reviews etc), evidence the human cares about (demos etc), and finally the actual implementation code (human attention here depends). The pull to just start building is usually the signal that the map is done. Some forks in the divergent plan can be answered on your own; see below.
Unless the user says otherwise, do everything in a git worktree at `worktrees/<adjective_noun_{1-3 word description of the work, e.g. snuggly_snail_scene_edit, bad_badger_nvim_rust_analyzer}>/` , define this as the <worktree name> henceforth in the project repo (same name as the plan), leaving the main checkout untouched. Branch name is also <worktree name> as well.
Generate the adjective and noun pair via `qz generate-name`.
Once coined retitle this session via the `name_session` tool as `Adjective Noun: <short description>`.
The short description can be longer than the 1-3 word description used in the worktree name; soft cap of ~5-8 words.
Both descriptions, the worktree and the session title, name the work, not the plan, e.g. `Furious Fennec: portal renderer`
- Prototypes let the user answer questions and are thrown away. These are a deliverable produced at handoff time, they are better than directly asking questions when it comes to matters of taste/personal preference, e.g. layout of a GUI. To produce these, use the `gui-automation` skill, first to test them internally, then at handoff provide a split, e.g. several variations of the prototype and the user picks. Make sure to draw attention to the prototype via one of your batched questions e.g. A or B.
- Demos illustrate a UI, flow, or otherwise graphical feature — see the `demo` skill. Use whenever a fork, node, or the handoff hinges on something the user must see to judge (layout, interaction, sequencing, feel): a demo beats a verbal question, and an interactive demo beats side-by-side static windows. Build one unprompted whenever the plan's subject is itself visual.
- Chores unblock a decision (provisioning, signing up, updating dependencies). Do the ones you can then batch the human-only ones into the handoff.
- Experiments answer questions a plan waits on and can be answered by running real code, not by asking. **Experiment before you fork:** test the actual thing and observe the result. The cheapest experiments go first: CLI, anything headless. GUIs are more complicated.
  - **Web UIs** — drive with the `web-browser-use` skill.
  - **Desktop GUIs** — Two types: agent facing, such as to iterate and check whether a GUI is "done". An agent can get 90% of the way there by self-checking the GUI themselves. Secondly, spawning the GUI to handoff to the user to inspect/give feedback. Drive both with the `gui-automation` skill.
  - Phone Apps - ask the user to provide an (Android) phone with USB debugging capabilities ; test in the UI in a loop via installing over ADB -> launching the App -> manually test the feature/functionality/take a screenshot
  - **The residue is taste.** Micro-interactions, game feel, UX feel; things an agent cannot judge. Don't ask mid-flight. Instead, it becomes a fork whose options are **side-by-side user-facing windows** (see `gui-automation`) with slightly different interaction semantics, labelled A, B, C… — arbitrarily many, soft cap around 8; two is just the common case since most choices are roughly binary. The user picks one at handoff and the fork collapses.
  - Some things cannot be answered, for example micro-interactions, game feel, ux feel; things an agent cannot judge should become a fork in the plan. Side-by-side user-facing windows at handoff for the user to judge (see `gui-automation`) are the gold standard. Soft cap of ~5 choices per fork but 2 is the most common case (binary choice). The user picks at handoff (via a question) and by evaluating the deliverable.
- Prior art is invaluable, use the `web_search` tool, `gh` CLI, the `scout` skill for specific repos, and the `web-browser-use` skill for complex web tasks. Prior art search investigates if a similar problem has already been solved, and if so how, what learnings are applicable? Can we just reuse their answer, take it on as a dependency or rewrite but drawing heavy inspiration? Or is it an example of what not to do? You should **always** investigate prior art unless there is a good reason not to.
- Scratch work, any temporary files, e.g. one off scripts for an experiment (exception is the `scout` skill usage which follows that skill's guidance), use `worktrees/<worktree_name>/.scratch/`, which is gitignored. Prefer python, bash or typescript for scripts.
The plan itself gets written to `worktrees/<worktree_name>/.scratch/PLAN.md`, updated continuously as you go, treat the document as durable state, so compaction runs don't clear. The plan is not for the human to read. Instead, its a written record that serves as grounding context for subagents, and survives compaction runs for the main agent.

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

### 2 · Expand, and work alone, for a long time

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
  - In dotfiles repo, topics are specifically per program, e.g. "nvim: X" never smaller scope than that.
  - In nix_config repo, per system or package in pkgs (or "workspace: X").
  - In larger workspaces (e.g. rust), per crate, or a general "workspace: X" for general cargo changes or updating dependencies for example

## Code as design (this section only applies to Game Development-adjacent tasks)
Conceptually, Code Review has two jobs: catching bugs and building human understanding of the codebase for code the human did not write. In most work, the first dominates, and evidence+human signoff is plenty sufficient. But for games, the code's expression and organisation shapes the product: Conway's Law. For example a damage formula's structure, the order of application of damage threshold and % reduction matters. And here the human must review the code, not just the evidence. So to minimise human time and energy, you'll need to:
* Flag expression-sensitive nodes (and their location in the code). This includes formulae, data layout, naming conventions and ordering.
* At handoff highlight code that requires particular attention and explain design consequences and their expression, not just behaviour.
* Prefer human-readable structure even at agent cost.

## Compute done.
To prove that your work is correct, you'll need to compute "doneness". Additionally, you'll need evidence of this, not purely a claim because you believe it to be correct, or it looks correct. 2 guiding principles: at least 1 of the below "doneness" computations per logical commit (more is better, and reduces the chance of human feedback causing further iteration). And as many different kinds as possible, especially across the whole body of work. E.g. in a client+server change: unit and integration test the server, computer use for the client. Remember, the goal is to minimise human attention, time and energy; so the more evidence of doneness, the better.
Before any handoff, you'll need to check using the following 7 kinds of "doneness" computation (do all that make sense):
1. Computer use (yourself). The `gui-automation` skill covers the specifics, including for web-UIs (gui-automation VM should have chromium). Examples of work: clicking through menus, buttons, dropdown, textboxes and submission of forms all work. The UI's layout and theming is appropriate and as expected.
2. Computer use (`general` subagent). Repeat 1 with a `general` subagent that also performs the tasks; give them the context and what tasks to complete. A separate check from 1, do both.
3. Standard CI, including unit and integration tests.
4. One-off (bash/typescript/python) scripts that compute a particular result. The language choice is independent of the language of the implementation. An example of this is implementation of an asset processing tool; then to test, write a bash script that calls the asset processing tool + downloads an asset to pass into the tool, then verify output including programmatically, for example, for a texture: compute size/format/compression etc. Then if the texture has some kind of meaning (includes for example AO/normals etc) when visible: pass to an `image` subagent as well.
5. Throwaway unit or integration tests, written in the same language as implementation. Example of this is a quick throwaway test that checks that Y+ direction is "up" when it's otherwise unclear what direction gravity is pulling in a game. Or a second example: a quick visual test that a texture's appearance ingame is correctly mapped (via screenshot + `image` subagent) (this differs from computer use, in that you only care about a rendering of the texture, and not its use in the wider game).
6. Web demo, see the `demo` skill. For when human taste, judgement, game feel, ux etc. are needed and there isn't an existing GUI (also used above for pre-implementation signoff).
7. Fork demo of an existing GUI, e.g. a game. For when human taste, judgement, game feel, ux etc. are needed and there is an existing GUI. Modify your worktree's copy with 2 kinds of modifications: the first are the changes you want human feedback on e.g. new UI layout / new gameplay mechanic etc. Second are necessary modifications that are hacked in and never merged upstream (thrown away once you get the user's feedback). Example: a new gameplay mechanic, and modification to the menu flow to launch the game straight into a brand new demo level. Demo level and menu flow changes are thrown away, game mechanic is not. Doneness here is human signoff.

## Post-implementation
Before handoff back to the user, rerun a `review` subagent then challenge its findings with `review-reflect`, and for a large block of work repeat until every flagged finding is fixed. If an issue resurfaces that you previously fixed: fix it again, but it doesn't count toward this stop condition. At handoff, flag to the user any issue you had to fix multiple times (especially if it's still not fixed).

Fix at the source. In order of places to fix:
  - Make the mistake impossible to occur in the code: for external data parse don't validate. Make invalid states unrepresentable.
  - Fix via CI: a new test, or lint. For mykaelium, this might include a new custom dylint.
  - Cover the hole via a new entry in the per-project LEARNINGS.md (in project root).


## Landing and Cleanup
Land your changes into main by rebasing onto main. Always rebase over merge.
```bash
git switch <branch> && git rebase main    # replay branch onto main's tip
git switch main && git merge --ff-only <branch>   # advance main's pointer — no merge commit

```
Once the work has landed, and the user says explicitly to (prompt them by asking them to) delete the worktree (and its directory):
```bash
git worktree remove worktrees/<worktree_name> && rmdir worktrees/<worktree_name> 2>/dev/null || true
git branch -d <worktree_name>                           # works after a rebase+ff landing; refuses if landing didn't happen
git branch -D <worktree_name>                           # only if the user squash-landed: originals aren't on main, -d refuses

```
Additionally, ensure you delete any artifacts you created in /tmp if they exist.
