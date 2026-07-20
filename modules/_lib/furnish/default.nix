{
  lib,
  resolve,
  resolveSystem,
}:
let
  contract = import ./contract.nix { inherit lib; };
  core = import ./core.nix {
    inherit
      lib
      contract
      resolve
      resolveSystem
      ;
  };
in
{
  inherit contract core;
  inherit (core) compile;

  # Runtime behavior starts with the coordinator work; importing the pure core
  # must not install one or make an empty declaration set observable.
  runtime = { };
}
