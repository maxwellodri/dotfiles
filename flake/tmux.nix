{ pkgs }:

let
  plugins = pkgs.symlinkJoin {
    name = "tmux-plugins";
    paths = with pkgs.tmuxPlugins; [ resurrect continuum ];
  };
in
{
  packages = {
    tmux = pkgs.tmux;
    inherit plugins;
    tmux-env = pkgs.symlinkJoin {
      name = "tmux-env";
      paths = [ pkgs.tmux plugins ];
    };
  };
}
