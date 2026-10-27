{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      praxis = inputs.lexicon.lib.praxis (
        (import ../../praxis.nix { inherit inputs pkgs; }) // { inherit pkgs; }
      );
    in
    {
      inherit (praxis) packages apps;
    };

  den.aspects.feltfomo.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.praxis ];
    };
}
