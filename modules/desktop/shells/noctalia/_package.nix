{ inputs, pkgs }:
inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./profile-state.patch ];
})
