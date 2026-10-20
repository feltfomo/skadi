{ inputs, ... }:
{
  # use the live checkout, including when invoked outside /etc/skadi.
  cwd = "/etc/skadi";
  scope = "global";
  commands = {
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
      description = "Update all inputs: praxis flake update";
      command = [
        "nix"
        "flake"
        "update"
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
