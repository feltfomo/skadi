{ ... }:
{
  flake.modules.nixos.graalvm-oracle-21 =
    { ... }:
    {
      nixpkgs.overlays = [
        (final: prev: {
          graalvm-oracle-21 = prev.graalvmPackages.buildGraalvm {
            version = "21";
            pname = "graalvm-oracle";
            src = final.fetchurl (import ./_hashes.nix)."21".${prev.stdenv.system};
            meta.platforms = builtins.attrNames (import ./_hashes.nix)."21";
            meta.license = prev.lib.licenses.unfree;
          };
        })
      ];
    };
}
