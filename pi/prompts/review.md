---
description: AI code review via review + reflect subagents (chain)
argument-hint: "[git-target | natural-language request]"
---
Run an AI code review using two subagents in **chain** mode: `review` then `review-reflect`.

Review request: `$@`

First, resolve the request into a concrete **diff target** (a `git diff` rev-range/pathspec) and an optional **review focus** (prose guidance on what to emphasize or what the change does):

- **Blank** (no args): target = staged changes (`git diff --cached`) if any exist, else the last commit (`HEAD~1..HEAD`). No focus.
- **Recognizable git target** — contains `..`, or is `--cached`/`--staged`, a commit SHA, or a path/glob (e.g. `main..HEAD`, `HEAD~3..HEAD -- '*.ts'`, `src/`, `.`): use it **verbatim** as the target. Normalize a bare SHA (no `..`) to `<sha>~1..<sha>`. No focus unless the text also carries prose.
- **Natural language** (e.g. "only review in this directory", "review the staged auth changes", "focus on token handling in the last 3 commits"): translate it into a target + optional focus:
  - A directory ("this directory", "here", a named dir) → that pathspec (`.` for the current dir).
  - "staged" → `--cached`; "last commit" → `HEAD~1..HEAD`; "last N commits" → `HEAD~N..HEAD`; "against main" / "since main" → `main..HEAD`.
  - A theme/area that isn't a literal path ("auth", "token handling") → **review focus**, not a pathspec. Run `git diff --name-only` first if it helps map the prose to actual paths.
  - Default rev when only a pathspec is implied: staged-or-last-commit.

Say one line before fanning out: `Reviewing <target>` (+ `(focus: …)` if any). When the target was auto-chosen, tell me which you picked.

Then call the `subagent` tool in **chain** mode with exactly two steps:
1. `agent: "review"` — task: `Review the git diff for <TARGET>.` (append ` Extra review focus: <FOCUS>.` if any). The review subagent runs `git-numbered-diff` itself; do not pre-run the diff for it.
2. `agent: "review-reflect"` — task: `The diff target is <TARGET>. Validate and filter this review of <TARGET>:\n\n{previous}`

Return the **reflected** review (step 2's output) to me **verbatim** — that is the final, de-noised review. Do not summarize it away or paraphrase it. If step 2 dropped findings, I want to see the `## Dropped` section.
