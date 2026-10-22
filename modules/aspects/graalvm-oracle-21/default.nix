{
  den.aspects.graalvm-oracle-21.nixos = _: {
    nixpkgs.overlays = [
      (
        final: prev:
        let
          # patchelf 0.19.2 creates overlapping LOAD mappings in Oracle's native-image.
          patchelf = prev.patchelf.overrideAttrs (old: {
            version = "${old.version}-patched";
            src = prev.fetchFromGitHub {
              owner = "NixOS";
              repo = "patchelf";
              rev = "3e996dbef1fa0658012f8dd290bddcf0302acade";
              hash = "sha256-+c7LIYKu0pYnG7h1dsEIDs6l4+91Vh/oDrSDARdBK3o=";
            };
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.autoreconfHook ];
          });
        in
        {
          graalvm-oracle-21 =
            (prev.graalvmPackages.buildGraalvm {
              version = "21";
              pname = "graalvm-oracle";
              src = final.fetchurl (import ./_hashes.nix)."21".${prev.stdenv.hostPlatform.system};
              meta.platforms = builtins.attrNames (import ./_hashes.nix)."21";
              meta.license = prev.lib.licenses.unfree;
            }).overrideAttrs
              (old: {
                nativeBuildInputs = [ patchelf ] ++ old.nativeBuildInputs;
              });
        }
      )
    ];
  };
}
