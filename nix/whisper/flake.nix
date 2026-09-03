{
  description = "Transcription env for yts: whisper.cpp (Vulkan) + ffmpeg + yt-dlp";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              whisper-cpp-vulkan
              ffmpeg
              yt-dlp
            ];

            # GPU via Vulkan: use nixpkgs' own mesa driver (RADV) so the loader,
            # ICD and driver all come from the store instead of mixing with the
            # host's (nix ld.so cannot resolve the host ICD's relative paths).
            env = {
              VK_DRIVER_FILES = "${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json";
              LD_LIBRARY_PATH = "${pkgs.mesa}/lib";
              # whisper.cpp 1.9.x dynamic backend loading does not reliably
              # pick up libggml-vulkan.so on its own; point it there directly.
              GGML_BACKEND_PATH = "${pkgs.whisper-cpp-vulkan}/lib/libggml-vulkan.so";
            };
          };
        });
    };
}
