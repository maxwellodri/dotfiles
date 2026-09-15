#!/bin/bash
############################
# Installs/updates pi (pi.dev) via nix.
#
# pi/flake/flake.nix builds the pi npm package hermetically — node, npm and
# tsc all come from the flake, so no pacman nodejs/npm/typescript are needed
# (uv still comes from the host; the blender MCP server needs it). Re-running
# this script is the updater: it checks the npm registry for a newer release,
# bumps the pinned version + hashes in pi/flake/flake.nix and rebuilds.
# The result is linked at pi/flake/result — the `scripts/pi` wrapper runs it.
#
# Also runs on every bootstrap regardless:
#   - vendored pi-mcp-adapter deps (node_modules is gitignored by design;
#     see pi/.gitignore) — npm ci via the flake's bundled npm
#   - VDH chromium extension unpack for pi/browser/playwright-config.json's
#     --load-extensions (missing dir = "Manifest file is missing or
#     unreadable" spam on every browser launch)
############################

set -eu

dir="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)"
flake="$dir/pi/flake"

: "${XDG_DATA_HOME:=$HOME/.local/share}"; export XDG_DATA_HOME

if ! command -v nix >/dev/null 2>&1; then
    echo "nix not found — install it first (see archlinux_x86_64_packages)" >&2
    exit 1
fi

# Flakes only see git-tracked files; an untracked flake.nix yields confusing
# "file not found" errors rather than a build.
if ! git -C "$dir" ls-files --error-unmatch pi/flake/flake.nix >/dev/null 2>&1; then
    echo "pi/flake/flake.nix is not tracked by git — run: git add pi/flake" >&2
    exit 1
fi

command -v uv >/dev/null 2>&1 ||
    echo "WARNING: uv not found — the blender MCP server needs it" >&2

# --- Update check ---------------------------------------------------------
# Latest release per the npm registry; the flake pins the version.
registry_latest() {
    curl -fsSL "https://registry.npmjs.org/@earendil-works/pi-coding-agent/latest" |
        jq -r .version
}

# dist.integrity for name@version straight from the packument.
registry_integrity() { # registry_integrity <name> <version>
    curl -fsSL "https://registry.npmjs.org/$1" |
        jq -r --arg v "$2" '.versions[$v].dist.integrity'
}

current="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$flake/flake.nix" | head -n1)"
latest="$(registry_latest)"

if [ "$current" = "$latest" ]; then
    echo "pi $current is the latest release"
else
    echo "Updating pi: $current -> $latest"

    # Regenerate integrities.json from the NEW tarball's npm-shrinkwrap.json:
    # upstream omits `integrity` for the @earendil-works workspace siblings,
    # and nixpkgs' npm-deps fetcher refuses those. Sibling versions may differ
    # from pi's own, so read them from the lock instead of assuming.
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/pi.tgz" \
        "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-$latest.tgz"
    tar -xzf "$tmp/pi.tgz" -C "$tmp" package/npm-shrinkwrap.json

    missing_integrities='
      [.packages | to_entries[]
       | select((.value.resolved // "") | test("registry.npmjs.org"))
       | select(.value | has("integrity") | not)]
    '
    jq -r "$missing_integrities |
        sort_by(.key) | .[] |
        [(.key | split(\"node_modules/\") | last), .value.version] | @tsv
    " "$tmp/package/npm-shrinkwrap.json" > "$tmp/deps.tsv"
    need="$(wc -l < "$tmp/deps.tsv")"
    while IFS="$(printf '\t')" read -r name ver; do
        ih="$(registry_integrity "$name" "$ver")"
        [ -n "$ih" ] && [ "$ih" != "null" ] ||
            { echo "no dist.integrity for $name@$ver on the registry" >&2; exit 1; }
        printf '%s\t%s\n' "$name" "$ih"
    done < "$tmp/deps.tsv" > "$tmp/integrities.tsv"
    got="$(wc -l < "$tmp/integrities.tsv")"
    [ "$need" = "$got" ] || { echo "integrity fetch incomplete ($got/$need)" >&2; exit 1; }
    jq -Rn '[inputs | split("\t") | select(length == 2) | {key: .[0], value: .[1]}] | from_entries' \
        "$tmp/integrities.tsv" > "$flake/integrities.json"

    # Bump the version; blank the hashes so the build below fails with fresh
    # "got: sha256-..." values that get fed back in automatically.
    for attr in version srcHash npmDepsHash; do
        if [ "$attr" = version ]; then new="$latest"; else
            new="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        fi
        sed -i "s|^\([[:space:]]*\)$attr = \"[^\"]*\";|\1$attr = \"$new\";|" "$flake/flake.nix"
    done
    trap - EXIT
    rm -rf "$tmp"
fi

# --- Build (with hash autofix) --------------------------------------------
# First build after a version bump fails on the tarball hash, the next on the
# npm-deps hash; each failure reports the correct value, so absorb them.
# tee mirrors nix's output to stderr so progress stays visible (a machine's
# first build fetches ~400MB of npm deps and takes a while); pipefail keeps
# nix's exit status through the pipe.
set -o pipefail
echo "Building pi via nix — first build on a machine fetches ~400MB of deps, be patient..."
attempt=0
while :; do
    if build="$(nix build "$flake#pi" --out-link "$flake/result" -L 2>&1 | tee /dev/stderr)"; then
        break
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -gt 3 ] || ! printf '%s\n' "$build" | grep -q '^ *got: *sha256-'; then
        printf '%s\n' "$build" >&2
        echo "nix build failed (see above)" >&2
        exit 1
    fi
    got="$(printf '%s\n' "$build" | sed -n 's/^ *got: *\(sha256-[^ ]*\)/\1/p' | head -n1)"
    if printf '%s\n' "$build" | grep -q 'hash mismatch.*npm-deps\.drv'; then
        attr=npmDepsHash
    else
        attr=srcHash
    fi
    echo "absorbing $attr -> $got"
    sed -i "s|^\([[:space:]]*\)$attr = \"[^\"]*\";|\1$attr = \"$got\";|" "$flake/flake.nix"
done

echo "pi $latest built: $(readlink "$flake/result")"

# Legacy npm-managed installs from the pre-nix installer; informational only.
for legacy in "$XDG_DATA_HOME/npm/bin/pi" "$HOME/.local/bin/pi"; do
    if [ -x "$legacy" ]; then
        echo "Note: old npm-managed pi at $legacy — safe to remove (nix build is now canonical)"
    fi
done

# --- Vendored pi-mcp-adapter deps -----------------------------------------
# node_modules is gitignored (reinstalled per machine). npm comes from the
# flake toolchain — no host npm needed.
adapter="$dir/pi/vendor/pi-mcp-adapter"
if [ -f "$adapter/package.json" ] && [ ! -d "$adapter/node_modules" ]; then
    echo "Installing vendored pi-mcp-adapter deps..."
    (cd "$adapter" && nix shell "$flake#toolchain" -c npm ci --omit=dev)
fi

# --- Extension typecheck (non-fatal) --------------------------------------
if ! nix run "$flake#typecheck" -- "$dir/pi/extensions"; then
    echo "WARNING: pi extension typecheck failed — see errors above" >&2
fi

# --- Chromium extension (Video Download Helper) ---------------------------
# For the playwright MCP browser. Path must match pi/browser/
# playwright-config.json's --load-extension. Idempotent: skip when an
# unpacked copy (manifest.json present) exists. CRX = binary header + plain
# zip, so cut at the first zip magic and unzip.
vdh_dir="$XDG_DATA_HOME/pi-browser-extensions/vdh"
if [ -f "$vdh_dir/manifest.json" ]; then
    echo "Chromium extension (VDH) already installed ($vdh_dir)"
else
    echo "Installing Chromium extension (VDH)..."
    tmp="$(mktemp -d)"
    zip_magic="$(printf 'PK\003\004')"
    if curl -fsSL -o "$tmp/vdh.crx" \
        'https://clients2.google.com/service/update2/crx?response=redirect&prodversion=131.0.6778.85&acceptformat=crx2,crx3&x=id%3Dlmjnegcaeklhafolokijcfjliaokphfk%26uc%3D' &&
        zip_at="$(grep -abo "$zip_magic" "$tmp/vdh.crx" | head -n1 | cut -d: -f1)" &&
        tail -c "+$((zip_at + 1))" "$tmp/vdh.crx" > "$tmp/vdh.zip" &&
        unzip -q "$tmp/vdh.zip" -d "$tmp/vdh"
    then
        mkdir -p "$(dirname "$vdh_dir")"
        rm -rf "$vdh_dir"  # partial/unmanifested leftovers only (manifest checked above)
        mv "$tmp/vdh" "$vdh_dir"
    else
        echo "VDH install failed — pi browser will warn about a missing extension" >&2
    fi
    rm -rf "$tmp"
fi
