{ lib, ... }:
{
  # DHCP so the install has substituter access and the box boots networked.
  # hostName mkDefault'd so den (or a later rename) can override without conflict.
  networking = {
    hostName = lib.mkDefault "generic";
    networkmanager.enable = true;
  };
}