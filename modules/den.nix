{
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.den.flakeModule ];

  # home-manager owns packages and program modules
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  # the shared state version stays pinned
  den.default.homeManager.home.stateVersion = "25.11";
  den.default.nixos.system.stateVersion = "25.11";
}
