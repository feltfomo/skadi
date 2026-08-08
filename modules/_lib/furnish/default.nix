{
  lib,
  resolve,
  resolveSystem,
}:
let
  ownerships = import ../ownerships { inherit lib; };
  krisis = import ../krisis { inherit lib; };
  axiom = import ../axiom { inherit lib; };
  contract = import ./contract.nix { inherit lib; };
  core = import ./core.nix {
    inherit
      lib
      contract
      krisis
      axiom
      resolve
      resolveSystem
      ;
    inherit (ownerships) claimKeys;
  };
in
{
  inherit contract core;
  inherit (core) compile;

  # the file lifecycle layer.
  files = import ./files.nix { inherit lib contract; };

  # runtime behavior starts with the coordinator work; importing the pure core
  # must not install one or make an empty declaration set observable.
  runtime = import ./runtime.nix;
}
