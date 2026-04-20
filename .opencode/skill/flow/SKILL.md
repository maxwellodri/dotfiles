---
name: flow
description: Clone a git repository and search through it to answer questions.
---

# Flow — Clone & Search Repositories

## Workflow

When the user invokes `/skill:flow <repo> <question>` or asks to clone and search a repo, follow these steps **in order**:

### 1. Resolve the Repository URL

- If the input is already a git URL (contains `://` or starts with `git@`), use it as-is.
- Otherwise treat the input as a `<owner>/<repo>` or bare `<repo>` shorthand:
  - Bare name like `pi` → resolve to `https://github.com/badlogic/pi-mono.git` using `gh repo view <name> --json url` or ask the user for the owner.
  - `owner/repo` → `https://github.com/<owner>/<repo>.git`
- If resolution fails, ask the user for the full URL.

### 2. Determine the Local Path

Derive a directory name from the repo URL:
- Strip trailing `.git`
- Take the last two path segments (`owner/repo`) joined by `-`
- Example: `https://github.com/badlogic/pi-mono.git` → `badlogic-pi-mono`

Local base directory: `~/.cache/repositories/`

### 3. Clone or Reuse

```bash
# Check if repo already exists
if [ -d "$HOME/.cache/repositories/<derived-name>/.git" ]; then
  echo "Repository already cloned at ~/.cache/repositories/<derived-name>"
else
  # Ensure parent dirs exist
  mkdir -p "$HOME/.cache/repositories"
  git clone <repo-url> "$HOME/.cache/repositories/<derived-name>"
fi
```

If the repo exists `git pull` to update it.

### 4. Search & Answer

With the repo cloned, answer the user's question by:

1. First exploring the repo structure (`ls`, `find`, `tree`) to understand its layout.
2. Using `grep`, `rg`, or reading files directly to find relevant code.
3. Synthesizing a clear answer with file paths and line references.

**Always show the local path** to the repo so the user knows where it lives.

## Example Usage

```
/skill:flow badlogic/pi-mono How does the agent handle tool calls?
/skill:flow https://github.com/modelcontextprotocol/servers.git What servers are available?
/skill:flow pi What's the project structure?
```

## Notes

- Repos are cloned shallow (`--depth 1`) unless the user needs full history.
- The `~/.cache/repositories/` directory is used so repos persist across sessions.
- If disk space is a concern, remind the user they can `rm -rf ~/.cache/repositories/<name>` when done.
