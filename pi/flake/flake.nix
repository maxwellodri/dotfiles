{
  description = "pi coding agent (pi.dev): nix-built binary + extension toolchain";

  # nixpkgs pin. Update: nix flake lock --update-input nixpkgs (from this dir).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # Version/hash edits are automated by helper_scripts/install_pi.sh (the
      # updater): it bumps `version`, then feeds the "got: sha256-..." lines
      # from failed builds back into the corresponding hash attributes. Only
      # touch these by hand to pin a specific release.
      version = "0.85.1";
      srcHash = "sha256-H0mHKWSb3OZH0RYJk7TZK/PGFMyBkhO+4vkd008qevQ=";
      npmDepsHash = "sha256-/9Y0z0AsOc+G6IOn2PqksLYziJJ83YtAHBnXGGyepuU=";

      tarball = system: nixpkgs.legacyPackages.${system}.fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
        hash = srcHash;
      };
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nodejs = pkgs.nodejs_24; # pi needs >=22.19

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
                 // error("no integrity for \(name($k)) — regenerate pi/flake/integrities.json"));
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
            src = tarball system;
            inherit nodejs;
            inherit postPatch npmDepsHash;
            nativeBuildInputs = [ pkgs.jq ];
            npmDeps = pkgs.fetchNpmDeps {
              name = "pi-coding-agent-${version}-npm-deps";
              src = tarball system;
              inherit postPatch;
              hash = npmDepsHash;
              nativeBuildInputs = [ pkgs.jq ];
            };
            # dist/bundle/cli.js is prebuilt by upstream — skip `npm run build`
            # (it would try to run tsgo + monorepo bundling scripts).
            dontNpmBuild = true;

            # pi spawns node/npx/npm as children (MCP servers via npx, package
            # installs): give it the nix-bundled node so no host nodejs is
            # needed. Children inherit this PATH.
            makeWrapperArgs = "--prefix PATH : ${pkgs.lib.makeBinPath [ nodejs ]}";
          };

          # node + npm + tsc for everything around pi: `npm ci` for the vendored
          # pi-mcp-adapter, tsc for extension type checking.
          #   nix shell <flake>#toolchain -c npm ci --omit=dev
          toolchain = pkgs.symlinkJoin {
            name = "pi-toolchain";
            paths = [ nodejs pkgs.typescript ];
          };
        in
        {
          pi = pi;
          default = pi;
          toolchain = toolchain;
        });

      # Type-check the repo's pi/extensions against the nix-built pi's type
      # definitions. Replaces the old tsconfig paths that pointed at the
      # npm-global install (a home path that won't exist on nix-only
      # machines). Extends the repo tsconfig (strictness, include) and just
      # swaps in the store paths.
      #   nix run <flake>#typecheck            (extensions dir = $PI_CODING_AGENT_DIR/extensions)
      #   nix run <flake>#typecheck -- /path/to/pi/extensions
      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          piRoot = "${self.packages.${system}.pi}/lib/node_modules/@earendil-works/pi-coding-agent";
        in
        {
          typecheck = {
            type = "app";
            program = toString (pkgs.writers.writeBash "pi-typecheck" ''
              set -euo pipefail
              extdir="''${1:-''${PI_CODING_AGENT_DIR:-}/extensions}"
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
                    "@earendil-works/pi-coding-agent": [ "${piRoot}/dist/index.d.ts" ],
                    "@earendil-works/pi-agent-core": [ "${piRoot}/node_modules/@earendil-works/pi-agent-core/dist/index.d.ts" ],
                    "@earendil-works/pi-tui": [ "${piRoot}/node_modules/@earendil-works/pi-tui/dist/index.d.ts" ],
                    "@earendil-works/pi-ai": [ "${piRoot}/node_modules/@earendil-works/pi-ai/dist/compat.d.ts" ],
                    "typebox": [ "${piRoot}/node_modules/typebox/build/index.d.mts" ]
                  }
                }
              }
              EOF
              # tsc resolves include/extends paths against the config they
              # were declared in, so the inherited "include": ["**/*.ts"]
              # still points at $extdir.
              ( cd "$extdir" && tsc --project "$tmp/tsconfig.json" )
            '');
          };
        });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = [ self.packages.${system}.toolchain ];
          };
        });
    };
}
