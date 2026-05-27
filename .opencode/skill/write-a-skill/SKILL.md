---
name: write-a-skill
description: "Create new opencode agent skills with proper structure, progressive disclosure, and bundled resources. Use when the user wants to create, write, or build a new skill."
---

# Writing Skills

## Process

1. **Gather requirements** - ask user about:
   - What task/domain does the skill cover?
   - What specific use cases should it handle?
   - Does it need executable scripts or just instructions?
   - Any reference materials to include?

2. **Draft the skill** - create:
   - `SKILL.md` with YAML frontmatter and concise instructions
   - Additional reference files if the skill has branching logic or distinct domains
   - Utility scripts if deterministic operations are needed

3. **Review with user** - present draft and ask:
   - Does this cover your use cases?
   - Anything missing or unclear?
   - Should any section be more/less detailed?

## Skill Structure

```
.opencode/skill/<skill-name>/
├── SKILL.md           # Main instructions (required, YAML frontmatter)
├── REFERENCE.md       # Detailed docs (if needed)
├── EXAMPLES.md        # Usage examples (if needed)
└── scripts/           # Utility scripts (if needed)
    └── helper.sh
```

## SKILL.md Template

```md
---
name: skill-name
description: Brief description of capability. Use when [specific triggers].
---

# Skill Name

## Quick start

[Minimal working example]

## Workflows

[Step-by-step processes with checklists for complex tasks]

## Advanced features

[Link to separate files: See [REFERENCE.md](REFERENCE.md)]
```

## Description & Triggers

The description is **the only thing the agent sees** when deciding which skill to load. It's surfaced in `<available_skills>` in the system prompt alongside all other installed skills. The agent reads these descriptions and picks the relevant skill based on the user's request.

**Goal**: Give the agent just enough info to know:

1. What capability this skill provides
2. When to trigger it (optional — see below)

**Format**:

- Max 1024 chars
- Write in third person
- First sentence: what it does
- Second sentence (optional): `"Use when [specific triggers]"`

### Triggers are optional

Not every skill needs auto-triggering. Some skills are better invoked explicitly by the user. After drafting the skill, **ask the user**:

> Should we include a trigger like `"Use when [suggested trigger]"`, or none at all?

If the user wants no trigger, the description covers capability only and the skill is loaded by explicit invocation.

**Good example with trigger**:

```
Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.
```

**Good example without trigger**:

```
Create new opencode agent skills with proper structure, progressive disclosure, and bundled resources.
```

**Bad example**:

```
Helps with documents.
```

The bad example gives the agent no way to distinguish this from other document skills.

## When to Add Scripts

Add utility scripts when:

- Operation is deterministic (validation, formatting, API calls)
- Same code would be generated repeatedly
- Errors need explicit handling

Scripts save tokens and improve reliability vs generated code.

## When to Split Files

Split into separate files when:

- Content has distinct domains (e.g. finance schemas vs sales schemas)
- Branching logic where the agent needs to decide between sub-documents
- Advanced features that are rarely needed and would bloat the main file

A big skill with lots of steps but a single cohesive topic is fine in one file, even at 250+ lines. Don't split just for length — split for **complexity**.

If SKILL.md grows beyond 200-300 lines AND has content that fits the criteria above, consider splitting.

## Review Checklist

After drafting, verify:

- [ ] Frontmatter has `name` and `description`
- [ ] Description clearly states capability
- [ ] Trigger included or explicitly opted out (ask user)
- [ ] No time-sensitive info
- [ ] Consistent terminology
- [ ] Concrete examples included
- [ ] Split into multiple files only if distinct domains or branching logic
- [ ] Scripts added only for deterministic, repeatable operations
