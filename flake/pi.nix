{ self, pkgs }:

let
  # Version/hash edits are automated by helper_scripts/install_flake.sh (the
  # updater): it bumps `version`, then feeds the "got: sha256-..." lines
  # from failed builds back into the corresponding hash attributes. Only
  # touch these by hand to pin a specific release.
  version = "0.85.1";
  srcHash = "sha256-H0mHKWSb3OZH0RYJk7TZK/PGFMyBkhO+4vkd008qevQ=";
  npmDepsHash = "sha256-/9Y0z0AsOc+G6IOn2PqksLYziJJ83YtAHBnXGGyepuU=";

  tarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = srcHash;
  };

  nodejs = pkgs.nodejs_24; # pi needs >=22.19

  # npm's supply-chain cooldown for everything pi spawns through npm/npx
  # (package installs, MCP servers): version resolution only picks
  # releases at least this many DAYS old (npm >= 11.10; the env var sits
  # below CLI flags and above ~/.npmrc). pi's own `pi update --self` and
  # managed-installer `npm ci` pass --min-release-age=0 explicitly and
  # stay exempt; `npm ci` on pinned lockfiles ignores the gate, so the
  # vendored-adapter installs are unaffected.
  npmMinReleaseAgeDays = 7;

  # The published npm-shrinkwrap.json is prod-only (no devDependencies
  # entries, though package.json still lists them — `npm ci` refuses
  # that mismatch) and omits `integrity` for the @earendil-works
  # workspace siblings (nixpkgs' prefetcher requires integrity on
  # every registry dep). postPatch fixes both; it must run identically
  # in the deps FOD (network, hash fixed by npmDepsHash) and the build
  # (offline), so integrities.json is committed rather than fetched.
  postPatch = ''
    jq --slurpfile integ ${./integrities.json} '
      def name($k): $k | split("node_modules/") | last;
      def integ($k):
        ($integ[0][name($k)]
         // error("no integrity for \(name($k)) — regenerate flake/integrities.json"));
      .packages |= with_entries(
        if (.value.resolved != null) and (.value | has("integrity") | not)
        then .value.integrity = integ(.key)
        else . end)
    ' npm-shrinkwrap.json > npm-shrinkwrap.json.tmp
    mv npm-shrinkwrap.json.tmp npm-shrinkwrap.json
    jq 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  # The pi package: the npm tarball ships dist/ prebuilt (no build
  # step); `npm ci` materialises node_modules, which pi needs at
  # runtime (extension loading resolves typebox/pi-agent-core/...
  # from it).
  pi = pkgs.buildNpmPackage {
    pname = "pi-coding-agent";
    inherit version;
    src = tarball;
    inherit nodejs;
    inherit postPatch npmDepsHash;
    nativeBuildInputs = [ pkgs.jq ];
    npmDeps = pkgs.fetchNpmDeps {
      name = "pi-coding-agent-${version}-npm-deps";
      src = tarball;
      inherit postPatch;
      hash = npmDepsHash;
      nativeBuildInputs = [ pkgs.jq ];
    };
    # dist/bundle/cli.js is prebuilt by upstream — skip `npm run build`
    # (it would try to run tsgo + monorepo bundling scripts).
    dontNpmBuild = true;

    # pi spawns node/npx/npm as children (MCP servers via npx, package
    # installs): give it the nix-bundled node so no host nodejs is
    # needed. Children inherit this PATH (and the cooldown env var).
    makeWrapperArgs = "--set npm_config_min_release_age ${toString npmMinReleaseAgeDays} --prefix PATH : ${pkgs.lib.makeBinPath [ nodejs ]}";
  };
in
{
  packages = {
    inherit pi;

    # node + npm + tsc for everything around pi: `npm ci` for the vendored
    # pi-mcp-adapter, tsc for extension type checking.
    #   nix shell <flake>#toolchain -c npm ci --omit=dev
    toolchain = pkgs.symlinkJoin {
      name = "pi-toolchain";
      paths = [ nodejs pkgs.typescript ];
    };
  };

  # Type-check the repo's pi/extensions against the nix-built pi's type
  # definitions. Replaces the old tsconfig paths that pointed at the
  # npm-global install (a home path that won't exist on nix-only
  # machines). Extends the repo tsconfig (strictness, include) and just
  # swaps in the store paths.
  #   nix run <flake>#typecheck            (extensions dir = $PI_CODING_AGENT_DIR/extensions)
  #   nix run <flake>#typecheck -- /path/to/pi/extensions
  apps.typecheck = {
    type = "app";
    program = toString (pkgs.writers.writeBash "pi-typecheck" ''
      set -euo pipefail
      extdir="$(realpath "''${1:-''${PI_CODING_AGENT_DIR:-}/extensions}")"
      if [ ! -f "$extdir/tsconfig.json" ]; then
        echo "pi-typecheck: no tsconfig.json in '$extdir'" >&2
        echo "usage: nix run <flake>#typecheck -- <pi/extensions dir>  (or set PI_CODING_AGENT_DIR)" >&2
        exit 1
      fi
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT
      cat > "$tmp/tsconfig.json" <<EOF
      {
        "extends": "$extdir/tsconfig.json",
        "compilerOptions": {
          "paths": {
            "@earendil-works/pi-coding-agent": [ "${pi}/lib/node_modules/@earendil-works/pi-coding-agent/dist/index.d.ts" ],
            "@earendil-works/pi-agent-core": [ "${pi}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core/dist/index.d.ts" ],
            "@earendil-works/pi-tui": [ "${pi}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui/dist/index.d.ts" ],
            "@earendil-works/pi-ai": [ "${pi}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/compat.d.ts" ],
            "typebox": [ "${pi}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/typebox/build/index.d.mts" ]
          }
        }
      }
      EOF
      # tsc isn't on this script's PATH (writers.writeBash adds no
      # packages) — call the nixpkgs typescript binary directly.
      # tsc resolves include/extends paths against the config they
      # were declared in, so the inherited "include": ["**/*.ts"]
      # still points at $extdir.
      ( cd "$extdir" && ${pkgs.lib.getExe pkgs.typescript} --project "$tmp/tsconfig.json" )
    '');
  };
}
