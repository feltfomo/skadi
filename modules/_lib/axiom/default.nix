{ lib }:
let
  validation = import ./validation.nix { inherit lib; };
  schema = import ./schema.nix { inherit lib validation; };
  identity = import ./identity.nix { inherit lib; };
  requirements = import ./requirements.nix { inherit lib; };
  registry = import ./registry.nix { inherit lib validation; };
  canonical = import ./canonical.nix { inherit lib; };
  phases = import ./phases.nix { inherit lib validation; };
  tagged = import ./tagged.nix { inherit lib; };
in
{
  inherit
    validation
    schema
    identity
    requirements
    registry
    canonical
    phases
    tagged
    ;
}
