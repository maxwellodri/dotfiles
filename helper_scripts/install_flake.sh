#!/bin/bash
set -eu

update=0
case "${1:-}" in
    --update) update=1 ;;
    "") ;;
    *) echo "usage: install_flake.sh [--update]" >&2; exit 2 ;;
esac

dir="$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)"
nixcfg="${NIX_CONFIG_DIR:-${SOURCE:-$HOME/source}/nix_config}"
pi_nix="$nixcfg/pkgs/pi/default.nix"
result="$nixcfg/dotfiles-env-result"
bin="${bin:-$HOME/bin}"

: "${XDG_DATA_HOME:=$HOME/.local/share}"; export XDG_DATA_HOME

if ! command -v nix >/dev/null 2>&1; then
    echo "nix not found — install it first (see archlinux_x86_64_packages)" >&2
    exit 1
fi

if [ ! -d "$nixcfg/.git" ]; then
    echo "nix_config not found at $nixcfg, exiting."
    exit 1
fi

command -v uv >/dev/null 2>&1 ||
    echo "WARNING: uv not found, blender MCP server needs it" >&2

# rename(2) swap so concurrent launches never observe a missing symlink
atomic_ln() { # atomic_ln <target> <linkpath>
    ln -s "$1" "$2.tmp.$$" && mv -T "$2.tmp.$$" "$2"
}

# dist.integrity for name@version straight from the packument.
registry_integrity() { # registry_integrity <name> <version>
    curl -fsSL "https://registry.npmjs.org/$1" |
        jq -r --arg v "$2" '.versions[$v].dist.integrity'
}

# Full packument (has the .time map the cooldown needs).
registry_packument() {
    curl -fsSL "https://registry.npmjs.org/@earendil-works/pi-coding-agent"
}

registry_latest() {
    curl -fsSL "https://registry.npmjs.org/@earendil-works/pi-coding-agent/latest" |
        jq -r .version
}

# --- Updates (--update only) ---------------------------------------------
# Plain runs never query the registry or touch the lock; the flake pins
# everything.
MIN_RELEASE_AGE_DAYS=7

current="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$pi_nix" | head -n1)"
pi_version="$current"

if [ "$update" = 1 ]; then
    # Refresh only the input feeding pkgs/* — dotfiles-env's deps (tmux,
    # firefox, thes, deemix, pi's toolchain) plus the pi/tmux-env/deemix-env
    # the vps installs from self.packages. The vps's own nixpkgs + deploy
    # tooling inputs stay put; their maintenance is delegated elsewhere.
    if (cd "$nixcfg" && nix flake update nixpkgs-dotfiles); then
        echo "nix_config nixpkgs-dotfiles input updated"
    else
        echo "WARNING: nix flake update nixpkgs-dotfiles failed — continuing on the existing lock" >&2
    fi

    # Newest plain x.y.z release published at least MIN_RELEASE_AGE_DAYS
    # days ago (registry .time has ISO timestamps with millis).
    cutoff=$(($(date +%s) - MIN_RELEASE_AGE_DAYS * 86400))
    target="$(registry_packument | jq -r --argjson cutoff "$cutoff" '
        .time | to_entries
        | map(select(.key | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))
        | map(select((.value | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) <= $cutoff))
        | map(.key) | join("\n")
    ' | sort -V | tail -n1)"
    [ -n "$target" ] || target="$current"

    latest="$(registry_latest || true)"
    if [ -n "$latest" ] && [ "$target" != "$latest" ]; then
        echo "npm cooldown: latest $latest is under ${MIN_RELEASE_AGE_DAYS}d old — considering $target"
    fi

    if [ "$target" != "$current" ]; then
        echo "Updating pi: $current -> $target"

        # Regenerate integrities.json from the NEW tarball's npm-shrinkwrap.json:
        # upstream omits `integrity` for the @earendil-works workspace siblings,
        # and nixpkgs' npm-deps fetcher refuses those. Sibling versions may differ
        # from pi's own, so read them from the lock instead of assuming.
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        curl -fsSL -o "$tmp/pi.tgz" \
            "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-$target.tgz"
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
            "$tmp/integrities.tsv" > "$nixcfg/pkgs/integrities.json"

        # Bump the version; blank the hashes so the build below fails with fresh
        # "got: sha256-..." values that get fed back in automatically.
        for attr in version srcHash npmDepsHash; do
            if [ "$attr" = version ]; then new="$target"; else
                new="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            fi
            sed -i "s|^\([[:space:]]*\)$attr = \"[^\"]*\";|\1$attr = \"$new\";|" "$pi_nix"
        done
        trap - EXIT
        rm -rf "$tmp"
        pi_version="$target"
    else
        echo "pi $current is the newest release at least ${MIN_RELEASE_AGE_DAYS}d old"
    fi
fi

# --- Build (with hash autofix) --------------------------------------------
# First build after a version bump fails on the tarball hash, the next on the
# npm-deps hash; each failure reports the correct value, so absorb them.
# tee mirrors nix's output to stderr so progress stays visible (a machine's
# first build fetches ~400MB of npm deps and takes a while); pipefail keeps
# nix's exit status through the pipe.
set -o pipefail
attempt=0
while :; do
    if build="$(nix build "$nixcfg#pi" --no-link -L 2>&1 | tee /dev/stderr)"; then
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
    sed -i "s|^\([[:space:]]*\)$attr = \"[^\"]*\";|\1$attr = \"$got\";|" "$pi_nix"
done

echo "Building dotfiles-env..."
nix build "$nixcfg#dotfiles-env" --out-link "$result" -L

echo "pi $pi_version built: $(readlink "$result")"

mkdir -p "$bin"

# stop the running daemon so the binary swap doesn't strand it on old code
# (mirrors tsp_ytdlp's old install.sh; no-op when not running)
if [ -x "$bin/tsp_ytdlp" ]; then
    "$bin/tsp_ytdlp" --kill >/dev/null 2>&1 || true
fi

atomic_ln "$result/bin/tmux" "$bin/tmux"
atomic_ln "$result/bin/deemix-cli" "$bin/deemix-cli"
atomic_ln "$result/bin/deemix-webui" "$bin/deemix-webui"
atomic_ln "$result/bin/dzq" "$bin/dzq"
atomic_ln "$result/bin/tsp_ytdlp" "$bin/tsp_ytdlp"
atomic_ln "$result/bin/yt-dlp-tsp" "$bin/yt-dlp-tsp"
atomic_ln "$result/bin/deemix-tsp" "$bin/deemix-tsp"
atomic_ln "$result/bin/markwatched" "$bin/markwatched"
atomic_ln "$result/bin/like" "$bin/like"
atomic_ln "$result/bin/git-surgeon" "$bin/git-surgeon"
atomic_ln "$result/share/tmux-plugins" "$dir/.config/tmux/plugins"
echo "tmux $("$bin/tmux" -V | awk '{print $2}'), plugins: $(readlink "$dir/.config/tmux/plugins")"
echo "deemix: dzq -> $(readlink "$bin/dzq")"
echo "tsp_ytdlp: $(readlink "$bin/tsp_ytdlp")"

# ARL -> ~/.config/deemix/login.json (sops-decrypted with the local gpg key)
if ! "$result/bin/deemix-arl-sync"; then
    echo "WARNING: deemix ARL sync failed — is the gpg key unlocked?" >&2
fi

# the profile is the dev-edition dedicated default (named
# dev-edition-default) — bare launches resolve it; the wrapper only keeps
# $bin/firefox ahead of any stray path resolution
cat > "$bin/firefox.tmp.$$" <<WRAPPER
#!/usr/bin/env bash
exec "$result/bin/firefox" "\$@"
WRAPPER
chmod +x "$bin/firefox.tmp.$$"
mv -T "$bin/firefox.tmp.$$" "$bin/firefox"
echo "firefox: $(cat "$bin/firefox" | tail -1)"

# relink profile config (user.js + chrome css) to the fresh store paths;
# dev-edition-default is the dedicated profile the browser always resolves
for prof in "$HOME"/.mozilla/firefox/*.dev-edition-default; do
    [ -d "$prof" ] || continue
    "$result/bin/firefox-rebuild-profile" "$prof"
done

# --- Fonts ---------------------------------------------------------------
# font-env ships the fonts + the RiceManFontFamily alias. Host fontconfig
# scans $XDG_DATA_HOME/fonts; ~/.config/fontconfig/fonts.conf is its user
# conf. Store paths change per build, so relink every run.
mkdir -p "$HOME/.config/fontconfig" "$XDG_DATA_HOME"
fonts_dir="$XDG_DATA_HOME/fonts"
if [ -e "$fonts_dir" ] && [ ! -L "$fonts_dir" ]; then
    echo "Moving existing $fonts_dir to temp directory"
    mv "$fonts_dir" "$(mktemp -d)/fonts"
fi
atomic_ln "$result/share/fonts" "$fonts_dir"
atomic_ln "$result/share/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
fc-cache -f
echo "fonts: $(readlink "$fonts_dir")"

# --- Vendored pi-mcp-adapter deps -----------------------------------------
# node_modules is gitignored (reinstalled per machine). npm comes from the
# flake toolchain — no host npm needed.
adapter="$dir/pi/vendor/pi-mcp-adapter"
if [ -f "$adapter/package.json" ] && [ ! -d "$adapter/node_modules" ]; then
    echo "Installing vendored pi-mcp-adapter deps..."
    (cd "$adapter" && nix shell "$nixcfg#toolchain" -c npm ci --omit=dev)
fi

# --- Extension typecheck (non-fatal) --------------------------------------
if ! nix run "$nixcfg#typecheck" -- "$dir/pi/extensions"; then
    echo "WARNING: pi extension typecheck failed — see errors above" >&2
fi

# --- Chromium extension (Video Download Helper) ---------------------------
# For the playwright MCP browser. Path must match pi/browser/
# playwright-config.json's --load-extension. Idempotent: skip when an
# unpacked copy (manifest.json present) exists. CRX = binary header + plain
# zip, so cut at the first zip magic and unzip.
# Drop stale service-worker/background script caches in every pi-browser
# profile (clones inherit the template's cache, so old code keeps running).
# Run after ANY extension patch; browsers must be closed.
clear_worker_caches() {
    local prof root
    for root in "${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright-mcp" \
                "$HOME/.cache/ms-playwright" /tmp/pi/chromium; do
        for prof in "$root"/*; do
            if [ -d "$prof/Default/Service Worker" ]; then
                rm -rf "$prof/Default/Service Worker"
            fi
        done
    done
}

# Bump the trailing version component so chromium discards its cached
# extension code after a patch. $1=manifest path, $2=component count (3 or 4)
bump_ext_version() {
    local manifest="$1" v="$2" out=""
    IFS=. read -ra parts <<<"$(jq -r .version "$manifest")"
    if ((${#parts[@]} == v && ${#parts[@]} > 0)); then
        parts[-1]=$((${parts[-1]} + 1))
        out="$(IFS=.; echo "${parts[*]}")"
        jq --arg v "$out" '.version = $v' "$manifest" > "$manifest.tmp" &&
            mv "$manifest.tmp" "$manifest"
    else
        echo "WARNING: could not parse version '$v' for post-patch bump ($manifest)" >&2
    fi
}

# Neuter the welcome/changelog tabs VDH opens on every fresh
# --load-extension install, and bump the version so chromium discards any
# cached (unpatched) service worker script. See
# .pi/skills/web-browser-use/TECHNICAL_DETAILS.md "VDH welcome tab".
# Patterns are against VDH 10.5.49.x minified main.js — warn if upstream
# changes them so the patch can be redone manually.
patch_vdh() {
    local main="$vdh_dir/service/main.js" manifest="$vdh_dir/manifest.json"
    sed -i \
        -e 's@if(t)H\.default\.tabs\.create({url:Dm}),H\.default\.storage\.local\.set({first_version_installed:r\.value})@if(t)H.default.storage.local.set({first_version_installed:r.value})@' \
        -e 's@(a||u)&&H\.default\.tabs\.create({url:km})@void(a\&\&u)@' \
        "$main"
    if grep -qE 'tabs\.create\(\{url:(Dm|km)\}\)' "$main"; then
        echo "WARNING: VDH welcome-tab patch did not match (new upstream build?)" >&2
        echo "  Re-patch manually per TECHNICAL_DETAILS.md, or the welcome tab returns." >&2
        return 0
    fi
    bump_ext_version "$manifest" 4
}

# Neuter the help page Dark Reader opens on every fresh-profile install.
# Pattern is against DR 4.9.13x (readable build, background/index.js).
patch_darkreader() {
    local js="$dr_dir/background/index.js"
    perl -0pi -e 's/chrome\.tabs\.create\(\{url: getHelpURL\(\)\}\);/void 0; \/\* patched: no help tab on install \*\//' "$js"
    if grep -q 'tabs\.create({url: getHelpURL()})' "$js"; then
        echo "WARNING: Dark Reader help-tab patch did not match (new upstream build?)" >&2
        echo "  Re-patch manually per TECHNICAL_DETAILS.md, or the help tab returns." >&2
        return 0
    fi
    bump_ext_version "$dr_dir/manifest.json" 3
}

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
        patch_vdh
    else
        echo "VDH install failed — pi browser will warn about a missing extension" >&2
    fi
    rm -rf "$tmp"
fi

# --- Chromium extensions (uBlock Origin, Dark Reader) ---------------------
# GitHub-release builds (CWS ships no full uBO for MV3-era chromium; the
# chromium zip is MV2 but still loads unpacked via --load-extension).
# Same idempotence rule: skip when an unpacked copy exists.
# Asset names: uBO embeds the version (resolve via API); DR's is static.
ext_dir="$XDG_DATA_HOME/pi-browser-extensions"
ubo_dir="$ext_dir/ublock"
dr_dir="$ext_dir/darkreader"

gh_latest_asset() { # $1=repo  $2=asset-name regex
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" |
        jq -r --arg re "$2" '.assets[].browser_download_url | select(test($re))' | head -n1
}

install_zip_ext() { # $1=zip-url  $2=dest  $3=inner-dir ('' if manifest at zip root)
    local url="$1" dest="$2" inner="$3" tmp
    tmp="$(mktemp -d)"
    if curl -fsSL -o "$tmp/ext.zip" "$url" && unzip -q "$tmp/ext.zip" -d "$tmp/unz"; then
        rm -rf "$dest"
        if [[ -n $inner && -d "$tmp/unz/$inner" ]]; then
            mv "$tmp/unz/$inner" "$dest"
        else
            mkdir -p "$dest" && mv "$tmp/unz"/* "$dest"/
        fi
        echo "installed: $dest"
    else
        echo "WARNING: extension install failed ($url)" >&2
    fi
    rm -rf "$tmp"
}

if [ -f "$ubo_dir/manifest.json" ]; then
    echo "Chromium extension (uBlock Origin) already installed ($ubo_dir)"
else
    echo "Installing Chromium extension (uBlock Origin)..."
    ubo_url="$(gh_latest_asset gorhill/uBlock 'chromium\.zip$')"
    [[ -n $ubo_url ]] && install_zip_ext "$ubo_url" "$ubo_dir" uBlock0.chromium
fi

if [ -f "$dr_dir/manifest.json" ]; then
    echo "Chromium extension (Dark Reader) already installed ($dr_dir)"
else
    echo "Installing Chromium extension (Dark Reader)..."
    dr_url="$(gh_latest_asset darkreader/darkreader '^darkreader-chrome-mv3\.zip$')"
    [[ -n $dr_url ]] && install_zip_ext "$dr_url" "$dr_dir" ""
    [[ -f "$dr_dir/manifest.json" ]] && patch_darkreader
fi

# Cached extension code is version-keyed; clearing once after any patch
# covers both. Browsers must be closed for a clean flush.
clear_worker_caches
