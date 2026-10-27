# Migrating ~/source → ~/Projects

Everything in the live config resolves the source tree through env vars:
`$SOURCE` (defined once in `.config/sh/shrc`, sourced by both zsh and bash),
`$dotfiles` (`.zprofile.<tag>` for login shells, re-exported by
`.zshrc_extra.<tag>` for non-login shells), and `$SOURCE` paths in
`.config/qz/config.yaml` (qz expands env vars via shellexpand).
`systemd --user` imports `SOURCE` (`.zshrc_extra.pc`), and
`scripts/_git_reminder.sh` falls back to `$HOME/source` if it runs before
any login shell. `~/source/private` is fully location-independent — every
script derives paths from `$0`/git-root/symlinks.

Remaining hardcodes are below. Work through this on migration day.

## 1. Definition sites — the only live places naming the old path

- `.config/sh/shrc:27` — `export SOURCE="$HOME/source"` (root definition)
- `.zprofile.pc:24-25`, `.zprofile.hackerman:22-23`, `.zprofile.donnie:14-15`,
  `.zprofile.nox:7` — `$dotfiles`/`$dotfile`. zprofile runs before shrc, so
  these cannot reference `$SOURCE`.

## 2. Formats with no env-var expansion

- `.config/git/config:12` — `core.excludesFile` (git config expands neither
  env vars nor `~` here)
- `.config/git/config:14` — `[remind] paths` (dead: nothing reads it — delete,
  or wire into `scripts/_git_reminder.sh`)
- `system_configs/etc/pacman.d/hooks/tlp.conf.hook:10` — runs as root, no user
  env exists. Edit, then re-apply system configs from nix_config:
  `~/source/nix_config/…/dotfiles-env…/bin/apply-system-configs <tag>`
  (system_configs moved from dotfiles to nix_config)

## 3. Prose and docs (grep for `~/source` after moving)

- `.pi/skills/dotfiles-config/SKILL.md` (several spots)
- `.pi/skills/web-browser-use/SKILL.md:143` — example command
- `pi/skills/analyze-sessions/SKILL.md:103` — example `--cwd`
- `~/source/private`: `.pi/skills/issue_cookies/SKILL.md:100`,
  `.pi/skills/newsboat-feeds/SKILL.md`, `reminders.rem:82`, `notes/index.md:55`
- `scripts/pi:11-12` — error-message text only; the logic is symlink-based
- `private/manifest.yaml` remotes are VPS-side paths — only relevant if the
  VPS reorganizes too

## 4. Dead hardcodes (unreachable; fix or delete at leisure)

- `.config/i3/config.laptop:38`, `.config/i3/config.thinkpad:38` — i3 is not
  linked on any live tag (makesymlinks' `$i3` meta vars are unused)
- legacy tag files: `*.{laptop,thinkpad,chromebook}` variants

## 5. Re-link procedure (absolute symlinks dangle after the move)

1. `mv ~/source/* ~/Projects/ && rmdir ~/source`
2. Section 1 + 2 edits; commit
3. apply system configs: `<nix_config>/scripts/install_flake.sh` then
   `dotfiles-env-result/bin/apply-system-configs <tag>`
4. `./install.sh <tag>` — recreates all `$HOME` and `$BIN` symlinks
5. private repo: `./install.sh` — session-dir symlink, cookies, maFiles,
   notes, reminders, newsboat urls, shrc.private
6. `./helper_scripts/install_flake.sh` — `PI_BIN` lives at
   `$dotfiles/flake/result/bin/pi`
7. Fresh shell; verify: `echo $SOURCE`, `qz`, `pi`, `systemctl --user show-environment | grep SOURCE`

## 6. Optional: XDG alignment

`~/.config/user-dirs.dirs` — set `XDG_PROJECTS_DIR="$HOME/Projects"` (or
`"$HOME/source"` if not moving). Local edits are retained across
`xdg-user-dirs-update` runs; `rmdir ~/Projects` if the updater created it.
