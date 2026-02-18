---
name: OpenCode Configuration Assistant
description: Helps with configuring opencode including using the official JSON schema available at https://opencode.ai/config.json
license: MIT
compatibility: opencode
metadata:
  audience: OpenCode Users
  workflow: configuration
  tech-stack: JSON Schema, OpenCode
---

# OpenCode Configuration Assistant

You are helping configure opencode using the official JSON schema.

**Note:** All coding standards from AGENTS.md apply unless explicitly overridden here.

## Configuration Scopes

OpenCode configuration can be applied at different scopes:

| Scope | Location | Description |
|-------|----------|-------------|
| Global | `.config/opencode/opencode.json` | Applies to all projects (symlinked to `~/.config/opencode/`) |
| Global | `.config/opencode/AGENTS.md` | Agent rules for all projects |
| Repo-specific | `.opencode/opencode.json` | Project-local configuration (this repo only) |
| Repo-specific | `.opencode/AGENTS.md` | Project-local agent rules |

### Symlink Structure (Global Config)

Global config files in this dotfiles repo are symlinked:

```
~/.config/opencode/opencode.json -> /home/maxwell/source/dotfiles/.config/opencode/opencode.json
~/.config/opencode/AGENTS.md -> /home/maxwell/source/dotfiles/.config/opencode/AGENTS.md
```

Note the .config/opencode directory itself is not symlinked (as it contains various bun/js cache files); only select files (as above) inside it.

### Determining Scope

When a user requests a configuration change, **infer the intended scope** and **confirm your understanding** before making changes:

- **Global** - Changes that should apply everywhere (e.g., default model, keybinds, permissions)
- **Repo-specific** - Changes only for this project (e.g., project-specific agents, formatters, MCP servers)

Signal your understanding to the user:
- "This seems like a global configuration tweak. Shall I apply it to `.config/opencode/opencode.json`?"
- "This seems like a dotfiles project-specific tweak. Shall I apply it to `.opencode/opencode.json`?"
- User may specify an external project path (e.g., `~/source/mykaelium`)

### Editing Configuration

**IMPORTANT:** Always edit files in this dotfiles repository, NOT the symlinked files in `~/.config/opencode/`.

When making configuration changes:
1. Determine the appropriate scope (global vs repo-specific)
2. Confirm your understanding with the user
3. Use Edit or Write tool on the appropriate file in this repo
4. Changes will automatically apply via the symlink (global) or be repo-local (`.opencode/`)

## OpenCode JSON Schema

The official opencode configuration schema is available at:

**https://opencode.ai/config.json**

When assisting with opencode configuration tasks, reference this schema to:
- Validate configuration options
- Understand available settings and their types
- Ensure proper configuration structure
- Identify required vs optional fields
- Verify default values and constraints

## Usage

When a user requests help with opencode configuration:
1. Fetch the latest schema from https://opencode.ai/config.json
2. Use it to guide configuration changes
3. Ensure all modifications comply with the schema structure
4. Provide explanations based on schema definitions where helpful
