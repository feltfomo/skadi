{ lib }:
let
  validation = import ./validation.nix { inherit lib; };
  identity = import ./identity.nix { inherit lib; };
  tagged = import ./tagged.nix { inherit lib; };
  canonical = import ./canonical.nix { inherit lib; };
in
{
  inherit
    validation
    identity
    tagged
    canonical
    ;
}
