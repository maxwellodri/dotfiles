---
name: git-surgeon
description: Dissect a dirty working tree into staged commits for user review. Never commits or performs destructive git operations. Never load unless the user explicitly prompts for it.
---

# git-surgeon

`git-surgeon` is a CLI for hunk-level git operations. In this skill it is used
as a **read-only inspector plus a staging engine**, nothing more. The agent
dissects a dirty tree into a series of logical commits; **the user is the
committer**.

## Core rules (read before doing anything)

1. **Never auto-load.** This skill runs only when the user explicitly directs.
2. **Read-only except for staging.** The ONLY non-read-only operations this
   skill ever performs:
   - `git-surgeon stage <id>...` — stage tracked hunks
   - `git-surgeon stage <id> --lines a-b` — stage part of a hunk
   - `git add <file>` — stage an untracked file (whole file, atomically)
3. **Everything else is FORBIDDEN.** Never run, in any form:
   `git-surgeon commit`, `commit-to`, `unstage`, `discard`, `fold`, `amend`,
   `reword`, `squash`, `undo`, `undo-file`, `split`, `move`; nor plain
   `git commit`, `git rebase`, `git reset --hard`, `git revert`, `git push`,
   etc. If a forbidden op seems necessary, STOP and ask the user.
4. **Never commit.** The user commits every group. You stage, you stop, you
   wait.
5. **No unattended iteration.** Stage one logical commit's worth, then yield.
   Do not pre-stage the next group while the user is reviewing.

## Preflight: verify a clean index

Before inspecting anything:

1. Run `git status --porcelain` (and/or `git diff --cached --stat`).
2. If ANY change is already staged, STOP and ask:
   > There are already staged changes. Do you want to (a) commit them
   > separately first, or (b) unstage them so I can inspect everything as one
   > pool?
3. Do not proceed until the index is clean AND the user confirms.

## The dissect workflow

Goal: turn one big dirty tree into N logical commits, serialized through the
index (git can't hold multiple staged-but-uncommitted groups at once).

### Phase 1 — Inspect

```bash
git status --porcelain          # all changes: modified + untracked
git-surgeon hunks               # tracked hunks with IDs, +/- counts, preview
git-surgeon hunks --blame       # which commit introduced the surrounding lines
git-surgeon show <id>           # full diff for one hunk, lines numbered
```

Use `show` on anything that needs a closer look. Use `--blame` when you suspect
new lines belong with an older commit (amend-style grouping).

### Phase 2 — Sample the repo's commit style

Before proposing any message, learn the conventions of THIS repo:

```bash
git log --pretty=format:'%s' -20
```

Note subject case, scope/prefix convention, length, tone, body presence. Match
that style for every proposed message. Do not assume a style — this dotfiles
repo uses kernel-style `scope: subject` lowercase with no conventional-commits
prefixes; other repos differ. Sample every time.

### Phase 3 — Plan all commits upfront

Present the full dissection plan as a numbered list BEFORE staging anything:

```
1. <proposed subject, repo style>
   - tracked hunks: <ids> / <files>
   - untracked (whole file): <files>
2. <proposed subject>
   - ...
```

Get overall approval (and edits) before iterating. Reshuffle the plan as
needed; only once the user signs off do you begin Phase 4.

### Phase 4 — Iterate one commit at a time

For each planned commit:

1. Announce: `Staging commit N/M: <subject>`.
2. Stage tracked hunks for this commit:
   ```bash
   git-surgeon stage <id1> <id2> ...
   git-surgeon stage <id> --lines 5-30   # for a partial hunk
   ```
3. Stage any untracked files that belong to this commit:
   ```bash
   git add <file1> <file2>
   ```
   Untracked files are atomic — the whole file goes into exactly one commit.
4. Verify the staged set matches the plan (nothing extra, nothing missing):
   ```bash
   git diff --cached --stat
   git-surgeon hunks --staged
   ```
5. STOP. Hand the user the suggested commit command with the proposed message:
   ```
   Review the staged changes, then commit (or ask me to adjust):
     git commit -m "<subject>" [-m "<body>"]
   ```
6. WAIT. Do not proceed to the next commit until the user confirms they
   committed.
7. After confirmation, re-run `git status --porcelain`. If the index is not
   clean again (user unstaged, made new edits, etc.), re-enter **Preflight**
   and ask how to proceed.
8. Move to the next planned commit. Repeat.

### Phase 5 — Wrap up

After the last commit:

1. `git status --porcelain` — confirm the tree is clean, or report leftover
   changes that didn't fit any logical commit.
2. Summarize the commits produced.
3. Stop. Never push, amend, reorder, or clean up.

## Partial hunks

When one file's diff spans multiple logical commits, split by line range:

1. `git-surgeon show <id>` — note the line numbers on the left.
2. `git-surgeon stage <id> --lines 5-30` — stage only that range now.
3. Remaining lines stay unstaged for a later commit in the plan.

## Grouping heuristics

- One logical change per commit (feature, bugfix, refactor, config tweak).
- Use `--blame` to cluster changes whose surrounding lines share an origin
  commit (amend-style grouping).
- Untracked files are atomic: the whole file lands in exactly one commit.
- When grouping is ambiguous, surface the ambiguity to the user before staging.
- Prefer smaller, self-contained commits over "drive-by" mixed changes.

## Hunk IDs

- 7-char hex, derived from file path + hunk content.
- Stable across runs until the diff content changes.
- Duplicates get `-2`, `-3` suffixes.
- If an ID isn't found, re-run `git-surgeon hunks` for fresh IDs.

## Command reference

The full `git-surgeon` command catalog lives in [REFERENCE.md](REFERENCE.md).
**Everything there except `hunks`, `show`, and `stage` is FORBIDDEN by this
skill's rules** — those commands are documented for reference only, e.g. when
the user asks you to suggest a command for them to run themselves.
