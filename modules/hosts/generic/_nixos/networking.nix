{ lib, ... }:
{
  # dhcp gives the installer substituter access and leaves the installed host networked.
  # hostName stays overridable for den and later host renames.
  networking = {
    hostName = lib.mkDefault "generic";
    networkmanager.enable = true;
  };
}
