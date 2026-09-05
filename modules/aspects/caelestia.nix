{
  inputs,
  program,
  rootPath,
  ...
}:
{
  flake-file.inputs = {
    # temporary transport override while git.outfoxxed.me is unavailable
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    caelestia = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell";
    };
  };

  den.aspects.caelestia = program {
    imports = [
      inputs.caelestia.homeManagerModules.default
      (
        { pkgs, ... }:
        let
          inherit (pkgs.stdenv.hostPlatform) system;
        in
        {
          programs.caelestia = {
            enable = true;
            package = inputs.caelestia.packages.${system}.with-cli;
            systemd.enable = false;
            cli.enable = true;
          };
        }
      )
    ];
    files = [
      {
        src = "${rootPath}/configs/caelestia/shell.json";
        dest = ".config/caelestia/shell.json";
        representation = "writable";
        onConflict = "source-wins";
      }
      {
        src = "${rootPath}/configs/caelestia/cli.json";
        dest = ".config/caelestia/cli.json";
        representation = "writable";
        onConflict = "source-wins";
      }
    ];
  };
}
