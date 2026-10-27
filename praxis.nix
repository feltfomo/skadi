{ inputs, pkgs, ... }:
let
  machines = [
    "khion"
    "lumi"
  ];
  user = "feltfomo";
  remote = {
    packages = [
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr
      pkgs.coreutils
      pkgs.openssh
      pkgs.fish
      pkgs.fzf
      pkgs.jq
    ];
    script = "modules/terminals/herdr/_praxis.fish";
    interpreter = "${pkgs.fish}/bin/fish";
    forwardArgs = false;
  };
in
{
  # use the live checkout, including when invoked outside /etc/skadi.
  cwd = "/etc/skadi";
  scope = "global";
  commands = {
    herdr = {
      machines = {
        description = "List configured Herdr SSH destinations";
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
      new = remote // {
        description = "Create and attach to a new named Herdr session";
        positional = [
          "machine"
          "session"
        ];
        parameters = {
          machine.choices = machines;
          session = { };
        };
        interactive = true;
        args = [
          "new"
          user
          { param = "machine"; }
          { param = "session"; }
        ];
      };
      sessions = remote // {
        description = "List running Herdr sessions on a machine";
        positional = [ "machine" ];
        parameters.machine.choices = machines;
        args = [
          "list"
          user
          { param = "machine"; }
        ];
      };
    }
    // pkgs.lib.genAttrs machines (
      machine:
      remote
      // {
        description = "Pick a running Herdr session on ${machine}, or attach by name";
        positional = [ "session" ];
        parameters.session.required = false;
        interactive = true;
        args = [
          "attach"
          user
          machine
          { param = "session"; }
        ];
      }
    );
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
    description = "Generate, format, check, then switch khion or lumi";
    lock = "skadi-rebuild";
    positional = [ "host" ];
    parameters.host.choices = [
      "khion"
      "lumi"
    ];
    steps = [
      "gen"
      "fmt"
      "check"
      {
        label = "Switch host";
        forwardArgs = true;
        confirm = "Switch this machine to the selected host configuration?";
        shell = ''exec nix run ".#$PRAXIS_ARG_HOST" -- switch "$@"'';
      }
    ];
  };
}
