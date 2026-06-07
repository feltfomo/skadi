{
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.den.flakeModule ];

  # feltfomo runs both home-manager and hjem
  den.schema.user.classes = lib.mkDefault [
    "homeManager"
    "hjem"
  ];

  # global state version, do not change
  den.default.homeManager.home.stateVersion = "25.11";
  den.default.nixos.system.stateVersion = "25.11";
}
