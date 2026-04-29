# Global Rules

## Plan Persistence Workflow

After completing a planning session, ask the user if they want to persist the plan to disk. These plans are generally gitignored.

If yes, when execution begins:
1. Create `.opencode/plans/` directory if it doesn't exist (via bash `mkdir -p`)
2. Write the plan to `.opencode/plans/YYYY-MM-DD-brief-description.md`
3. Then proceed with implementation

If no or no response: proceed directly to implementation without persisting.

## Plan File Template

Plans must follow this exact structure:

```markdown
# Context (READ-ONLY SECTION)
[Freeform markdown — all background, architecture decisions, relevant APIs, types,
conventions, crate location, dependencies, design rationale. Everything gathered
during planning that a junior engineer would need to understand the feature.]

# Tasks
[
  {
    "task": "Short description of the task",
    "completed": false,
    "steps": [
      "Step 1: ...",
      "Step 2: ..."
    ]
  }
]

# Progress
```

- **`# Context (READ-ONLY SECTION)`** — All background information required to understand and implement the feature.
- **`# Tasks`** — A JSON array of task objects. Each task has `task` (description), `completed` (boolean), and `steps` (detailed sub-steps).
- **`# Progress`** — Left empty. Appended to during implementation as a diary of findings.
