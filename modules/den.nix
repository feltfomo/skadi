{
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.den.url = "github:denful/den/v0.18.0";

  imports = [ inputs.den.flakeModule ];

  # home-manager owns packages and program modules
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  # feature aspects publish the paths their state needs; impermanence is the
  # single consumer that turns the aggregated declarations into bind mounts.
  den.quirks.persistence.description = "Impermanence paths declared by feature aspects";

  # the shared state version stays pinned
  den.default.homeManager.home.stateVersion = "25.11";
  den.default.nixos.system.stateVersion = "25.11";
}
