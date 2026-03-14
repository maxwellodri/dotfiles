---
name: Dotfiles Configuration
description: Guides modification of dotfiles configuration files managed via makesymlinks.sh
license: MIT
compatibility: opencode
metadata:
  audience: Dotfiles Users
  workflow: configuration
  tech-stack: Shell, Symlinks
---

# Dotfiles Configuration

You are helping modify configuration files in this dotfiles repository.

**Note:** All coding standards from AGENTS.md apply unless explicitly overridden here.

## Workflow

### 1. Git Safety Check

**Before starting any config modification:**

Run `git status --porcelain` to verify working tree is clean:
- **If dirty (any output):** REFUSE to proceed. Remind user to commit or stash current work.
- **If clean (no output):** Proceed to next step.

### 2. Determine Edit Location

**IMPORTANT:** Always edit files in this dotfiles repository (`~/source/dotfiles/`), NOT the symlinked locations in `$HOME`.

The symlink structure means:
```
~/.bashrc -> ~/source/dotfiles/.bashrc
~/.config/i3/config -> ~/source/dotfiles/.config/i3/config
~/.config/nvim/ -> ~/source/dotfiles/.config/nvim/
```

Editing the symlinked location edits the repo file, but it's clearer to work directly in the repo.

### 3. Symlink System Overview

The `helper_scripts/makesymlinks.sh` script manages symlinks:

| Variable | Symlink Path | Source File |
|----------|--------------|-------------|
| `i3config` | `~/.config/i3/config` | `.config/i3/config` |
| `zsh` | `~/.zshrc`, `~/.zshrc_extra`, etc. | `.zshrc`, `.zshrc_extra.<tag>`, etc. |
| `nvim` | `~/.config/nvim/` | `.config/nvim/` |
| `tmux` | `~/.config/tmux/` | `.config/tmux/` |
| `gitconfig` | `~/.config/git/` | `.config/git/` |
| `opencode` | `~/.config/opencode/opencode.json`, etc. | `.config/opencode/opencode.json`, etc. |

### 4. Tag/Platform System

Some configs are platform-specific. The tag is set by the first argument to makesymlinks.sh (`pc` or `hackerman`).

**Files that get tag suffixes:**

| File | Platform-specific source |
|------|-------------------------|
| `.bashrc_extra` | `.bashrc_extra.pc` or `.bashrc_extra.hackerman` |
| `.zshrc_extra` | `.zshrc_extra.pc` or `.zshrc_extra.hackerman` |
| `.zprofile` | `.zprofile.pc` or `.zprofile.hackerman` |
| `.config/i3status/config` | `.config/i3status/config.pc` or `.config/i3status/config.hackerman` |
| `.config/sh/shrc` | `.config/sh/shrc` (always, no suffix but mapped) |
| `.config/zathura/zathurarc` | `.config/zathura/zathurarc` (always, no suffix but mapped) |

**All other configs are shared across platforms.**

### 5. Adding a New Config

To add a new dotfile to the system:

1. **Add a variable** in the "Fixed Variables" section of `makesymlinks.sh`:
   ```sh
   mynewconfig=.config/myapp/config
   ```

2. **Add to appropriate meta variable** (or create new one):
   - `xfiles` - X11/GUI apps
   - `bash` - Bash-related
   - `zsh` - Zsh-related
   - `files` - General/CLI tools
   - Or add directly to `pcfiles`/`hackermanfiles`

3. **If platform-specific**, add a case in the symlink loop (around line 122):
   ```sh
   "$mynewconfig")  src="$dir/$file.$tag"
       ;;
   ```

4. **Run the script** to create the symlink:
   ```sh
   ./helper_scripts/makesymlinks.sh pc  # or hackerman
   ```

### 6. Editing Existing Configs

1. Locate the source file in this repo (see table in section 3)
2. Edit the file using Edit or Write tool
3. Changes are immediately active (symlink points to edited file)
4. No need to re-run makesymlinks.sh for content changes

### 7. Applying Symlink Changes

After modifying `makesymlinks.sh` itself (adding/removing configs):

```sh
./helper_scripts/makesymlinks.sh pc        # for pc platform
./helper_scripts/makesymlinks.sh hackerman # for hackerman platform
./helper_scripts/makesymlinks.sh clean     # remove all symlinks
```

The script:
- Creates backup of existing files in a temp directory
- Removes trailing slashes from directory paths
- Creates parent directories as needed
- Handles special cases with tag suffixes

### 8. After Completion

Suggest a kernel-style commit message (not conventional commits):

Examples:
- "makesymlinks: add support for alacritty config"
- "zsh: enable autosuggestions plugin"
- "nvim: add lsp configuration for rust-analyzer"
