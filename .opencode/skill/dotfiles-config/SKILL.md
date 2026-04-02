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

### 3. Editing Existing Configs

**For content changes to existing configs:**
1. Locate the source file in this repo
2. Edit the file using Edit or Write tool
3. Changes are immediately active (symlink points to edited file)
4. No need to re-run any installation scripts

### 4. Adding New Configs

**For adding NEW configs to the system:**
1. Add/modify files in the repo
2. Rerun `./install.sh "$dotfile_tag"` to reinstall everything

Or run specific script if you know which one:
- `./helper_scripts/makesymlinks.sh "$dotfile_tag"` - dotfile symlinks
- `./helper_scripts/custom_bin_scripts.sh` - user scripts
- `./helper_scripts/firefox_user.sh` - firefox configs
- `./helper_scripts/install_system_configs.sh` - system configs

### 5. After Completion

Suggest a kernel-style commit message (not conventional commits):

Examples:
- "makesymlinks: add support for alacritty config"
- "zsh: enable autosuggestions plugin"
- "nvim: add lsp configuration for rust-analyzer"

---

## Configuration Categories

### Dotfiles (Symlinked)

The `helper_scripts/makesymlinks.sh` script manages symlinks:

| Variable | Symlink Path | Source File |
|----------|--------------|-------------|
| `i3config` | `~/.config/i3/config` | `.config/i3/config` |
| `zsh` | `~/.zshrc`, `~/.zshrc_extra`, etc. | `.zshrc`, `.zshrc_extra.<tag>`, etc. |
| `nvim` | `~/.config/nvim/` | `.config/nvim/` |
| `tmux` | `~/.config/tmux/` | `.config/tmux/` |
| `gitconfig` | `~/.config/git/` | `.config/git/` |
| `opencode` | `~/.config/opencode/opencode.json`, etc. | `.config/opencode/opencode.json`, etc. |

**Tag/Platform System:**

Some configs are platform-specific. The current platform is available via the `$dotfile_tag` environment variable (set in `.zprofile`).

Available tags: `pc` or `hackerman`

**Files that get tag suffixes:**

| File | Platform-specific source |
|------|-------------------------|
| `.bashrc_extra` | `.bashrc_extra.pc` or `.bashrc_extra.hackerman` |
| `.zshrc_extra` | `.zshrc_extra.pc` or `.zshrc_extra.hackerman` |
| `.zprofile` | `.zprofile.pc` or `.zprofile.hackerman` |
| `.config/i3status/config` | `.config/i3status/config.pc` or `.config/i3status/config.hackerman` |
| `.config/sh/shrc` | `.config/sh/shrc` (always, no suffix but mapped) |
| `.config/zathura/zathurarc` | `.config/zathura/zathurarc` (always, no suffix but mapped) |

All other configs are shared across platforms.

**To add a new dotfile:**

1. Add a variable in the "Fixed Variables" section of `makesymlinks.sh`
2. Add to appropriate meta variable (`xfiles`, `bash`, `zsh`, `files`, or `pcfiles`/`hackermanfiles`)
3. If platform-specific, add a case in the symlink loop (around line 122)
4. Run `./helper_scripts/makesymlinks.sh "$dotfile_tag"`

### Neovim

**Config location:** `.config/nvim/`

**Entrypoints:**
- `init.vim` — main entrypoint. Manages plugins via vim-plug (`call plug#begin`/`call plug#end`), general vim settings, autocmds, and keybinds. Sources `lua/user/init.lua` at the end.
- `lua/user/init.lua` — Lua entrypoint. Requires all Lua modules (`lua/user/*.lua`) for LSP, cmp, treesitter, telescope, dap, etc.

**Plugin manager:** vim-plug (not lazy.nvim or packer). Plugins are declared in `init.vim`.

**Reading help docs from the CLI (for agents):**

Agents cannot interact with the nvim TUI. Use headless mode to print help to stdout:

```sh
# General pattern: print first N lines of a help topic
nvim --headless -c "help <topic>" -c "let lines=getline(1,80)" -c "echo join(lines,'\n')" -c "qa!"
```

- Adjust `80` to read more or fewer lines.
- Output contains escape sequences and help tags (`*tag*`, `|link|`) — these are normal vim help formatting.
- Use `grep`/`rg` on the output to find specific sections.

**Help topics for installed plugins:**

| Plugin | Help topic | Notes |
|--------|-----------|-------|
| Nvim built-in | `help`, `lsp`, `options`, `builtin`, `lua-guide` | Core Neovim help |
| mason.nvim | `mason.nvim` | LSP/DAP/linter/formatter manager |
| mason-lspconfig.nvim | `mason-lspconfig.nvim` | Bridges mason ↔ lspconfig |
| nvim-cmp | `nvim-cmp` | Autocompletion |
| LuaSnip | `luasnip` | Snippet engine |
| telescope.nvim | `telescope.nvim` | Fuzzy finder; also `telescope.builtin` |
| nvim-treesitter | `nvim-treesitter` | Parser/highlighting; also `nvim-treesitter-queries` |
| nvim-dap | `dap.txt` | Debug Adapter Protocol client |
| nvim-dap-ui | `dapui.txt` | DAP UI |
| oil.nvim | `oil.nvim` | File browser |
| nvim-tree | `nvim-tree` | File explorer |
| fugitive | `fugitive` | Git integration |
| lazygit | `lazygit.nvim` | LazyGit floating window |
| vim-surround | `surround` | Surrounding text objects |
| vim-eunuch | `eunuch` | Unix shell commands |
| lualine | `lualine` | Statusline |
| render-markdown | `render-markdown.nvim` | Markdown rendering |
| mkdnflow | `mkdnflow` | Markdown navigation |
| nvim-autopairs | `nvim-autopairs` | Auto-close brackets |
| none-ls | `none-ls` | Diagnostics/formatting via external tools |
| snacks.nvim | `snacks.nvim` | Utility plugin |
| vimtex | `vimtex` | LaTeX support |
| crates.nvim | `crates.nvim` | Cargo.toml crate management |
| lspkind | `lspkind` | LSP completion icons |
| dressing.nvim | `dressing.nvim` | UI improvements for vim.ui |
| img-clip | `img-clip.nvim` | Image clipboard/paste |
| nvim-treesitter-context | `nvim-treesitter-context` | Sticky context |

**Finding help topics:** If the topic name is unknown, try searching help tags:
```sh
# List all help tags matching a pattern
nvim --headless -c "helpgrep <pattern>" -c "let lines=getline(1,30)" -c "echo join(lines,'\n')" -c "qa!"
```

**Refreshing help tags** (after adding/removing plugins):
```sh
nvim --headless -c "helptags ALL" -c "qa!"
```

### User Scripts (Symlinked to `$bin`)

The `scripts/` directory contains utility scripts symlinked to `$bin` (typically `~/bin/`).

**Managed by:** `helper_scripts/custom_bin_scripts.sh`

**Requirements:**
- `$bin` and `$dotfiles` env vars must be set (from shell rc)
- Run `./helper_scripts/custom_bin_scripts.sh` after adding new scripts

**To add a new script:**
1. Add script file to `scripts/` directory
2. Run `./helper_scripts/custom_bin_scripts.sh`

### Firefox (Symlinked to profile)

The `firefox/` directory contains Firefox customization files.

**Files:**
- `user.js` - Firefox preferences
- `userChrome.css` - Browser UI styling
- `userContent.css` - Page content styling

**Managed by:** `helper_scripts/firefox_user.sh`

The script finds the default profile from `~/.mozilla/firefox/profiles.ini` and symlinks configs there.

**To modify Firefox configs:**
1. Edit files in `firefox/` directory
2. Changes are immediate (symlinked)
3. Run `./helper_scripts/firefox_user.sh` only if setting up on a new system

### System Configs (Copied, not symlinked)

Global system files are **copied** (not symlinked) because they require system-level permissions.

**Managed by:** `helper_scripts/install_system_configs.sh`

**Mappings:**

| Source | Destination | Notes |
|--------|-------------|-------|
| `udev-rules/` | `/etc/udev/rules.d` | Requires sudo |
| `systemd-services/system/` | `/etc/systemd/system` | Requires sudo, auto-manages services |
| `systemd-services/user/` | `~/.config/systemd/user` | No sudo, auto-manages services |
| `system_configs/etc/` | `/etc/` | Requires sudo |

**Service Management:**
- Automatically enables/starts/restarts affected services
- Backs up existing files before overwriting
- Requires `.dotfile_tag` file to exist (created by makesymlinks.sh)

**To modify system configs:**
1. Edit files in appropriate directory (`udev-rules/`, `systemd-services/`, `system_configs/`)
2. Run `./helper_scripts/install_system_configs.sh`

### Arch Linux Packages

Track required packages in `archlinux_x86_64_packages`.

**To install packages:**
- Use `pacman` directly: `sudo pacman -S <package>`
- The package list is for reference/automated reinstallation only

### Source Code Repositories

Store source code repositories in `$SOURCE` (typically `~/source`):
- This dotfiles repo: `~/source/dotfiles`
- Open source projects: `~/source/<project>`
- Personal projects: as appropriate

---

## Full Installation

To reinstall everything (e.g., on a new system):

```sh
./install.sh "$dotfile_tag"
```

**Installation order:**
1. `arch_package_install.sh` - Install packages
2. `makesymlinks.sh` - Dotfile symlinks
3. `custom_bin_scripts.sh` - Scripts to `$bin`
4. `firefox_user.sh` - Firefox profile setup
5. `rust/install.sh` - Rust toolchain
6. `install_system_configs.sh` - System configs (needs `.dotfile_tag`)
7. `download_suckless.sh` - Suckless tools (last, may prompt for SSH)
