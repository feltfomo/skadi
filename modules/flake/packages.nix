{
  config,
  lib,
  den,
  ...
}:
let
  recipes = config.skadi.packages;
  overlay = final: _: lib.mapAttrs (_: recipe: final.callPackage recipe { }) recipes;
in
{
  # features publish packages other features consume, so nothing imports across feature paths
  options.skadi.packages = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    description = "callPackage recipes added to every host's pkgs and to perSystem packages.";
  };

  config = {
    # home-manager uses the host's pkgs, so the host overlay reaches every home too
    den.aspects.skadi-packages.nixos.nixpkgs.overlays = [ overlay ];
    den.schema.host.includes = [ den.aspects.skadi-packages ];

    perSystem =
      { pkgs, ... }:
      {
        packages = lib.mapAttrs (_: recipe: pkgs.callPackage recipe { }) recipes;
      };
  };
}
