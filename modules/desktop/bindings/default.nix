{ lib, ... }:
{
  # compositors render the shared bindings for their own config syntax
  options.skadi.bindings = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = "Shared desktop bindings as a function of { lib, hostName }.";
  };
  config.skadi.bindings = import ./_binds.nix;
}
