Ensure your changes are staged in git.
## 1. First pass
Spawn the `review` agent (subagent tool, `agentScope: "both"` so project-level
review rules load) with target `--cached`. If I gave a focus area, pass it as
`Extra review focus: ...`. Summarize its findings tersely (severity, file:line,
one-liner). Fix nothing yet.

## 2. Discuss — arbitrate disputes, don't self-dismiss
Walk me through the findings. When you believe a finding is wrong or not worth
fixing, you are not the arbiter. Spawn `review-reflect` on just the contested
finding(s) (skip if there arent any). Paste the finding plus direction on whats being reviewed (i.e. staged changes)  , ask it to refute or keep. Drop a finding only if reflect actively refutes it (upstream guard,
impossible path, grep evidence); otherwise we fix it.

## 3. Fix + restage
Apply the fixes we agree on and restage. If fixes were substantial, rerun
`review` on the new `--cached`.

## 4. Learnings
If we reject a finding review finding (either reviewer), on taste or other subjective grounds, note it down in
`.pi/agents/review/learnings.md` (create if
absent) so future reviews skip that pattern.

Then stop. I'll do my own review pass. Dont commit, I'll do it.
