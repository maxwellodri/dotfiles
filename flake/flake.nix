{
  description = "dotfiles-wide flake: tmux + plugins, pi";

  # Update: helper_scripts/install_flake.sh --update (what `pi update` runs)
  # — rolls this lock (nixos-unstable; the lock pins the rev) plus the pi pin in pi.nix. Bare
  # `nix flake update` from this dir works for the lock alone.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      merged = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          tmux = import ./tmux.nix { inherit pkgs; };
          pi = import ./pi.nix { inherit self pkgs; };
        in {
          packages = tmux.packages // pi.packages // {
            default = pkgs.symlinkJoin {
              name = "dotfiles-env";
              paths = [ tmux.packages.tmux-env pi.packages.pi ];
            };
          };
          apps = pi.apps;
        };
    in {
      packages = forAllSystems (system: (merged system).packages);
      apps = forAllSystems (system: (merged system).apps);
    };
}
