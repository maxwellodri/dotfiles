---
name: scout
description: Use when the user asks to 'search the X repo', 'explore the X repo', 'look at the X repo', 'scout the X repo', 'what does X repo do', pastes a GitHub/repository URL (with or without a question), or mentions cloning and searching a repository. Supports GitHub owner/repo shorthand, bare names, and full git URLs.
---

# Scout — Clone & Explore Repositories

## Workflow

When the user asks to scout a repo, or pastes a repo URL with a question, follow these steps **in order**:

### 1. Resolve the Repository URL

- If the input is already a git URL (contains `://` or starts with `git@`), use it as-is.
- If the input is a GitHub page URL (e.g. `https://github.com/owner/repo`), convert to a clone URL by appending `.git`.
- Otherwise treat the input as a `<owner>/<repo>` or bare `<repo>` shorthand:
  - Bare name like `pi` → resolve to `https://github.com/earendil-works/pi.git` using `gh repo view <name> --json url` or ask the user for the owner.
  - `owner/repo` → `https://github.com/<owner>/<repo>.git`
- If the user describes a repo, without giving a url, use gh cli, falling back
  to websearch to find it if you dont know it
- If resolution fails, ask the user for the full URL.

### 2. Determine the Local Path

Derive a directory name from the repo URL:
- Strip trailing `.git`
- Take the last two path segments (`owner/repo`) joined by `-`
- Example: `https://github.com/earendil-works/pi.git` → `earendil-works-pi`

Local base directory: `~/.cache/repositories/`

### 3. Clone or Reuse

```bash
if [ -d "$HOME/.cache/repositories/<derived-name>/.git" ]; then
  echo "Repository already cloned at ~/.cache/repositories/<derived-name>"
else
  mkdir -p "$HOME/.cache/repositories"
  git clone --depth 1 <repo-url> "$HOME/.cache/repositories/<derived-name>"
fi
```

If the repo already exists, `git pull` to update it.

### 4. Search & Answer

With the repo cloned, answer the user's question by:

1. First exploring the repo structure (`ls`, `find`, `tree`) to understand its layout.
2. Using `grep`, `rg`, or reading files directly to find relevant code.
3. Synthesizing a clear answer with file paths and line references.

**Always show the local path** to the repo so the user knows where it lives.

## Notes

- Repos are cloned shallow (`--depth 1`) unless the user needs full history.
- The `~/.cache/repositories/` directory is used so repos persist across sessions.
- If disk space is a concern, remind the user they can `rm -rf ~/.cache/repositories/<name>` when done.
