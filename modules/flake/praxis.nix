{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      praxis = inputs.lexicon.lib.praxis (
        (import ../../praxis.nix { inherit inputs; }) // { inherit pkgs; }
      );
    in
    {
      inherit (praxis) packages apps;
      checks.praxis =
        let
          testPraxis = inputs.lexicon.lib.praxis (
            (import ../../praxis.nix { inherit inputs; })
            // {
              inherit pkgs;
              cwd = "/tmp";
            }
          );
        in
        pkgs.runCommand "skadi-praxis-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              diffutils
              gnused
            ];
            PRAXIS = "${testPraxis.package}/bin/praxis";
          }
          ''
            bash -euo pipefail ${../../tests/praxis.sh}
            touch "$out"
          '';
    };

  den.aspects.feltfomo.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.praxis ];
    };
}
