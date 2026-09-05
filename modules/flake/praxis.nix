{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      tasks = inputs.lexicon.lib.praxis {
        inherit pkgs;
        discoverRoot = "flake.nix";
        commands = {
          gen = {
            description = "Regenerate the flake-file manifest";
            steps = [
              {
                exec = [
                  "nix"
                  "run"
                  "--accept-flake-config"
                  ".#write-flake"
                ];
              }
            ];
          };

          fmt = {
            description = "Format the repository";
            steps = [
              {
                exec = [
                  "nix"
                  "fmt"
                  "--accept-flake-config"
                ];
              }
            ];
          };

          check = {
            description = "Run the complete Skadi flake check";
            steps = [
              {
                exec = [
                  "nix"
                  "flake"
                  "check"
                  "--accept-flake-config"
                  "-L"
                ];
              }
            ];
          };

          rebuild = {
            description = "Regenerate, format, check, and switch Khion";
            lock = "skadi-rebuild";
            steps = [
              { command = "gen"; }
              { command = "fmt"; }
              { command = "check"; }
              {
                exec = [
                  "nix"
                  "run"
                  "--accept-flake-config"
                  ".#khion"
                  "--"
                  "switch"
                ];
                interactive = true;
                confirm = "Switch Khion to the checked configuration?";
              }
            ];
          };
        };
      };
    in
    {
      packages = tasks.packages // {
        praxis = tasks.package;
      };

      apps = tasks.apps // {
        praxis = {
          type = "app";
          program = "${tasks.cli}/bin/praxis";
        };
      };
    };
}
