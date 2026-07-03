# Updating the bundled manual

This is a sub-skill. Follow it **only** when the user asks to fetch or update the
manual, or when `manual/` is missing and the user opts in to generating it. The
fetch clones ~240 MB — **never run it unprompted.**

## Prerequisites

- `git` and `pandoc` installed.
- `blender` on PATH (for version detection). If absent, ask the user for the
  version (major.minor, e.g. `5.1`), or use `main` for the development tip.

## Steps

### 1. Installed version

```bash
blender --version | head -1     # e.g. "Blender 5.1.2"
```

Take **major.minor** → `5.1`.

### 2. Bundled version

```bash
cat .pi/skills/blender-tutor/manual/VERSION 2>/dev/null || echo MISSING
```

### 3. Decide

- **MISSING** (or `manual/` absent) → fetch (step 4) with the installed major.minor.
- **installed == bundled** → **noop**: tell the user "manual is already at
  `<version>`." Stop here.
- **installed != bundled** → `rm -rf .pi/skills/blender-tutor/manual`, then
  fetch (step 4) with the installed major.minor.

### 4. Fetch

```bash
bash .pi/skills/blender-tutor/scripts/fetch_manual.sh <MAJOR.MINOR>
```

e.g. `fetch_manual.sh 5.1`. The script maps `5.1` → branch
`blender-v5.1-release`, shallow-clones, converts rST → GFM, and writes
`manual/VERSION`. It takes a few minutes (network-bound) and is idempotent — it
clears and regenerates `manual/` each run.

## Notes

- **Version → branch convention:** `<MAJOR.MINOR>` → `blender-v<MAJOR>.<MINOR>-release`.
  If that branch doesn't exist (odd/unreleased version), list real branches and
  pick the closest match:
  ```bash
  git ls-remote --heads https://projects.blender.org/blender/blender-manual.git
  ```
- **`main`** = development tip (unreleased Blender). Use only if the user
  specifically wants the dev manual.
- After a successful fetch, confirm with `cat manual/VERSION` and report the file
  count/size the script prints.
