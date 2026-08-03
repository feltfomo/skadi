{
  lib,
  descriptors ? null,
  relations ? null,
}:
let
  surface = import ./surface.nix {
    inherit lib descriptors relations;
  };
  unitImporter = import ./import-units.nix { inherit lib; };
in
{
  inherit (surface)
    mkResolve
    mkResolveSystem
    mkResolveTrace
    mkResolveSystemTrace
    mkResolveMatrix
    mkResolveSystemMatrix
    mkResolveStrict
    mkResolveSystemStrict
    mkResolveProfiled
    mkResolveSystemProfiled
    translate
    claimKeys
    define
    toRoster
    mkRoster
    ;
  inherit (unitImporter)
    importUnits
    importUnitSets
    ;
}
