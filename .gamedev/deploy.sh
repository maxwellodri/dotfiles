#!/usr/bin/env bash
# Deploys personal game-dev configs (.nvim.lua, git post-commit hook) into the
# mykaelium game repo via symlinks. Idempotent — safe to re-run.
#
# Override target repo with: MYKAELIUM_REPO=/path/to/repo .gamedev/deploy.sh

set -uo pipefail

GAME_REPO="${MYKAELIUM_REPO:-$HOME/source/mykaelium}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! git -C "$GAME_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $GAME_REPO is not a git repository." >&2
  echo "Set MYKAELIUM_REPO to override." >&2
  exit 1
fi

GAME_GIT_DIR="$(git -C "$GAME_REPO" rev-parse --absolute-git-dir)"
GAME_HOOKS_DIR="$GAME_GIT_DIR/hooks"
mkdir -p "$GAME_HOOKS_DIR"

backup_dir=""
backups_made=false

# link <source-file> <target-path> <backup-basename>
# Idempotent: skip if correct symlink, replace wrong symlink, back up regular file.
link() {
  local src="$1"
  local dest="$2"
  local backup_name="$3"

  if [ ! -e "$src" ]; then
    echo "Error: source $src not found" >&2
    return 1
  fi

  if [ -L "$dest" ]; then
    if [ "$(readlink -- "$dest")" = "$src" ]; then
      echo "ok: $dest already linked correctly"
      return 0
    fi
    echo "replacing symlink: $dest"
    rm -- "$dest"
  elif [ -e "$dest" ]; then
    [ -z "$backup_dir" ] && backup_dir="$(mktemp -d)"
    echo "backing up $dest -> $backup_dir/$backup_name"
    mv -- "$dest" "$backup_dir/$backup_name"
    backups_made=true
  fi

  ln -s "$src" "$dest"
  echo "linked: $src -> $dest"
}

link "$SCRIPT_DIR/.nvim.lua"   "$GAME_REPO/.nvim.lua"          "nvim.lua"
link "$SCRIPT_DIR/post-commit" "$GAME_HOOKS_DIR/post-commit"   "post-commit"

# Ensure hook source is executable — symlink exec uses target's mode bits.
chmod +x "$SCRIPT_DIR/post-commit"

echo
echo "Done."
if [ "$backups_made" = true ]; then
  echo "Backups: $backup_dir"
fi
