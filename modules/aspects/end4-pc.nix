{ inputs, lexicon, ... }:
let
  workspaceNumbers = map toString (inputs.nixpkgs.lib.range 1 10);
in
{
  flake-file.inputs.illogical-impulse.url = "github:feltfomo/illogical-impulse-shell-nix";

  den.aspects.end4-pc = lexicon {
    hosts = [
      "khion"
      "lumi"
    ];
    package =
      pkgs: inputs.illogical-impulse.packages.${pkgs.stdenv.hostPlatform.system}.end4-pc-runtime;
    nixos = [
      {
        value = {
          security.polkit.enable = true;
          services.accounts-daemon.enable = true;
          services.upower.enable = true;
        };
      }
    ];
    furnish.files = [
      {
        source = builtins.toFile "end4-pc-config.json" (
          builtins.toJSON {
            bar.workspaces = {
              shown = 10;
              numberMap = workspaceNumbers ++ workspaceNumbers;
            };
          }
        );
        destination = ".config/illogical-impulse/config.json";
        representation = "writable";
        onConflict = "runtime-wins";
      }
    ];
  };
}
