inputs:
inputs.flake-parts.lib.mkFlake { inherit inputs; } (
  { den, ... }:
  let
    denApi = inputs.lexicon.lib.den { inherit den; };
  in
  {
    imports = [ (inputs.import-tree ./modules) ];
    systems = [ "x86_64-linux" ];
    _module.args = {
      lexicon = inputs.lexicon.lib.lexicon.forDen { inherit den; };
      furnishRuntime = inputs.lexicon.lib.furnishRuntime { };
      inherit denApi;
    };
  }
)
