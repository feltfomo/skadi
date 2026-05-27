{ config, ... }:
{
  flake.modules.nixos.khion-modules = config.flake.factory.hostModules "khion";
  flake.modules.nixos.lumi-modules = config.flake.factory.hostModules "lumi";
}
