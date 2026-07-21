{
  den,
  lib,
  resolve,
  resolveSystem,
  ...
}:
let
  denLib = import ./_lib/den.nix { inherit den lib; };
  tests = import ./_lib/furnish/tests.nix {
    inherit
      lib
      resolve
      resolveSystem
      ;
    principalContexts = denLib.hostPrincipals {
      system = "x86_64-linux";
      host = "khion";
    };
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks.furnish-pure = pkgs.runCommandLocal "furnish-pure-tests" { } (
        assert tests.ok;
        "touch $out"
      );
      legacyPackages = lib.optionalAttrs (system == "x86_64-linux") {
        furnishCollisionEvidence = tests.collisionEvidence;
      };
    };
}
