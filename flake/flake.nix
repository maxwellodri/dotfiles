{
  description = "dotfiles-wide flake: tmux + plugins, pi";

  # Update: nix flake lock --update-input nixpkgs (from this dir).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/eaad089433ca2bb662274377d33df3d0e51ef28b";

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
