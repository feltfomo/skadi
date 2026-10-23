inputs:
inputs.flake-parts.lib.mkFlake { inherit inputs; } (
  { den, ... }:
  let
    ownerships = inputs.lexicon.lib.ownerships { };
    denApi = inputs.lexicon.lib.den { inherit den; };
    inherit (denApi) roster;
    resolve = ownerships.mkResolve roster;
    # system slices have a host principal without a user principal
    resolveSystem = ownerships.mkResolveSystem roster;
    resolvePrepared = ownerships.mkResolvePrepared roster;
  in
  {
    imports = [ (inputs.import-tree ./modules) ];
    systems = [ "x86_64-linux" ];
    _module.args = {
      rootPath = ./.;
      inherit
        resolve
        resolveSystem
        resolvePrepared
        ownerships
        roster
        ;
      lexicon = inputs.lexicon.lib.lexicon.forDen { inherit den; };
      program = inputs.lexicon.lib.program {
        inherit
          resolve
          resolveSystem
          resolvePrepared
          ;
        inherit (denApi) filePrincipals hostUserNames;
      };
      furnishRuntime = inputs.lexicon.lib.furnishRuntime { };
      inherit denApi;
    };
  }
)
