#!/usr/bin/env bash
# fetch_manual.sh — convert the official Blender manual (reStructuredText) for a
# given version into a greppable Markdown tree under ../manual/.
#
# Deliberately single-purpose: clone one version, convert rST -> GFM, write a
# VERSION marker, report. Version detection and the noop / rm-old / regenerate
# decisions are the agent's job — see ../UPDATING.md.
#
# Usage:
#   fetch_manual.sh <version>   # e.g. 5.1   ->  branch blender-v5.1-release
#   fetch_manual.sh <branch>    # e.g. blender-v5.1-release
#   fetch_manual.sh main        # development tip

set -euo pipefail

REPO="https://projects.blender.org/blender/blender-manual.git"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$SKILL_DIR/manual"

die() { echo "error: $*" >&2; exit 1; }

version="${1:-}"
[[ -n "$version" ]] || die "usage: $0 <version|branch>  (e.g. 5.1, blender-v5.1-release, main)"

# Resolve version -> branch.
if [[ "$version" == "main" || "$version" == blender-v*-release ]]; then
    branch="$version"
elif [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    branch="blender-v${version}-release"
else
    die "unrecognised version/branch '$version' (want '5.1', 'blender-v5.1-release', or 'main')"
fi

for cmd in git pandoc; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd is required (install it first)"
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> cloning blender-manual @ $branch (shallow)..."
git clone --depth 1 --branch "$branch" "$REPO" "$tmp/src"

src="$tmp/src/manual"
[[ -d "$src" ]] || die "no 'manual/' subdir in clone @ $branch (repo layout changed?)"

echo "==> regenerating $OUT_DIR ..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "==> converting rST -> GFM ..."
count=0
while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    out="$OUT_DIR/${rel%.rst}.md"
    mkdir -p "$(dirname "$out")"
    # Sphinx uses roles/directives pandoc doesn't know; discard pandoc warnings
    # and skip a file that fails outright rather than aborting the whole run.
    pandoc --from=rst --to=gfm --wrap=none "$f" -o "$out" 2>/dev/null || true
    count=$((count + 1))
done < <(find "$src" -type f -name '*.rst' -print0)

printf '%s\n' "$version" > "$OUT_DIR/VERSION"

size="$(du -sh "$OUT_DIR" | cut -f1)"
echo "==> done: $count markdown files ($size) at manual/, branch=$branch, version marker=$version"
