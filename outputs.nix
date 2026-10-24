inputs:
inputs.flake-parts.lib.mkFlake { inherit inputs; } (
  { den, ... }:
  let
    ownerships = inputs.lexicon.lib.ownerships { };
    denApi = inputs.lexicon.lib.den { inherit den; };
    inherit (denApi) roster;
  in
  {
    imports = [ (inputs.import-tree ./modules) ];
    systems = [ "x86_64-linux" ];
    _module.args = {
      rootPath = ./.;
      inherit
        ownerships
        roster
        ;
      lexicon = inputs.lexicon.lib.lexicon.forDen { inherit den; };
      furnishRuntime = inputs.lexicon.lib.furnishRuntime { };
      inherit denApi;
    };
  }
)
