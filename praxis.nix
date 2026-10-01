{ inputs, ... }:
{
  # use the live checkout, including when invoked outside /etc/skadi.
  cwd = "/etc/skadi";
  commands = {
    gen = {
      description = "Regenerate flake.nix from the module declarations";
      scope = "global";
      command = [
        "nix"
        "run"
        ".#write-flake"
      ];
      forwardArgs = false;
    };
    fmt = {
      description = "Format the repository";
      scope = "global";
      command = [
        "nix"
        "fmt"
      ];
    };
    check = {
      description = "Build the hosts and run the repository checks";
      scope = "global";
      command = [
        "nix"
        "flake"
        "check"
        "-L"
      ];
    };
    update = {
      description = "Update one input: praxis update input <input>";
      scope = "global";
      parameters = [
        {
          name = "action";
          positional = true;
          required = true;
          choices = [ "input" ];
        }
        {
          name = "input";
          positional = true;
          required = true;
          choices = builtins.attrNames inputs;
        }
      ];
      command = [
        "nix"
        "flake"
        "update"
        { param = "input"; }
      ];
      forwardArgs = false;
    };
    flake = {
      description = "Update all inputs: praxis flake update";
      scope = "global";
      parameters = [
        {
          name = "action";
          positional = true;
          required = true;
          choices = [ "update" ];
        }
      ];
      command = [
        "nix"
        "flake"
        { param = "action"; }
      ];
      forwardArgs = false;
    };
  };
  tasks.rebuild = {
    description = "Generate, format, check, then switch khion or lumi";
    scope = "global";
    lock = "skadi-rebuild";
    parameters = [
      {
        name = "host";
        positional = true;
        required = true;
        choices = [
          "khion"
          "lumi"
        ];
      }
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
