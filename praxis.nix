{ inputs, pkgs, ... }:
let
  inherit (import ./modules/terminals/herdr/_machines.nix) machines user;
in
{
  # use the live checkout, including when invoked outside /etc/skadi.
  cwd = "/etc/skadi";
  scope = "global";
  commands = {
    herdr = {
      machines = {
        description = "List the machines Herdr combines into one window";
        command = [
          "${pkgs.coreutils}/bin/printf"
          "%-8s %s\n"
        ]
        ++ pkgs.lib.concatMap (machine: [
          machine
          "${user}@${machine}"
        ]) machines;
        forwardArgs = false;
      };
    };
    gen = {
      description = "Regenerate flake.nix from the module declarations";
      command = [
        "nix"
        "run"
        ".#write-flake"
      ];
      forwardArgs = false;
    };
    fmt = {
      description = "Format the repository";
      command = [
        "nix"
        "fmt"
      ];
    };
    check = {
      description = "Build the hosts and run the repository checks";
      command = [
        "nix"
        "flake"
        "check"
        "-L"
      ];
    };
    update.input = {
      description = "Update one input: praxis update input <input>";
      positional = [ "input" ];
      parameters.input.choices = builtins.attrNames inputs;
      command = [
        "nix"
        "flake"
        "update"
        { param = "input"; }
      ];
      forwardArgs = false;
    };
    flake.update = {
      description = "Update flake inputs and the Wooting background service";
      shell = ''
        set -euo pipefail
        nix flake update "$@"
        exec nix run .#update-wooting
      '';
      forwardArgs = false;
    };
    update.wooting = {
      description = "Update the Wooting background service version and hash";
      command = [
        "nix"
        "run"
        ".#update-wooting"
      ];
      forwardArgs = false;
    };
  };
  tasks.rebuild = {
    description = "Format, then switch khion or lumi";
    lock = "skadi-rebuild";
    positional = [ "host" ];
    parameters.host.choices = [
      "khion"
      "lumi"
    ];
    steps = [
      "fmt"
      {
        label = "Switch host";
        forwardArgs = true;
        confirm = "Switch this machine to the selected host configuration?";
        shell = ''exec nix run ".#$PRAXIS_ARG_HOST" -- switch "$@"'';
      }
    ];
  };
}
