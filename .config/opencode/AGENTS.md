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
# Plan Title

## Objective
[Required] What we're accomplishing - 1-2 sentences.

## Context
[Required] Key decisions, clarifications, and constraints discovered during planning.

## Steps
[Required] Ordered implementation steps as a markdown numbered list:
1. First step
2. Second step
3. ...

## Notes
[Optional] Any relevant information for future reference.
```
