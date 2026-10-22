{ inputs, program, ... }:
let
  workspaceNumbers = map toString (inputs.nixpkgs.lib.range 1 10);
in
{
  flake-file.inputs.illogical-impulse.url = "github:feltfomo/illogical-impulse-shell-nix";

  den.aspects.end4-pc = program {
    hosts = [
      "khion"
      "lumi"
    ];
    pkg = pkgs: inputs.illogical-impulse.packages.${pkgs.stdenv.hostPlatform.system}.end4-pc-runtime;
    nixos = {
      security.polkit.enable = true;
      services.accounts-daemon.enable = true;
      services.upower.enable = true;
    };
    files = [
      {
        src = builtins.toFile "end4-pc-config.json" (
          builtins.toJSON {
            bar.workspaces = {
              shown = 10;
              numberMap = workspaceNumbers ++ workspaceNumbers;
            };
          }
        );
        dest = ".config/illogical-impulse/config.json";
        representation = "writable";
        onConflict = "runtime-wins";
      }
    ];
  };
}
