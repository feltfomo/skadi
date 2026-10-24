{
  inputs,
  lexicon,
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

  den.aspects.caelestia = lexicon {
    homeManager.imports = [
      inputs.caelestia.homeManagerModules.default
      (
        { pkgs, ... }:
        let
          inherit (pkgs.stdenv.hostPlatform) system;
          cli = inputs.caelestia.inputs.caelestia-cli.packages.${system}.default.overrideAttrs (old: {
            preBuild = (old.preBuild or "") + ''
              export SETUPTOOLS_SCM_PRETEND_VERSION
            '';
          });
        in
        {
          programs.caelestia = {
            enable = true;
            package = inputs.caelestia.packages.${system}.with-cli.override {
              caelestia-cli = cli;
            };
            systemd.enable = false;
            cli = {
              enable = true;
              package = cli;
            };
          };
        }
      )
    ];
    furnish.files = [
      {
        source = "${rootPath}/configs/caelestia/shell.json";
        destination = ".config/caelestia/shell.json";
        representation = "writable";
        onConflict = "source-wins";
      }
      {
        source = "${rootPath}/configs/caelestia/cli.json";
        destination = ".config/caelestia/cli.json";
        representation = "writable";
        onConflict = "source-wins";
      }
    ];
  };
}
