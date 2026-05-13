{ ... }:
{
  flake.nixosModules.lumiNetworking =
    { ... }:
    {
      networking = {
        hostName = "lumi";
        networkmanager.enable = true;
      };
    };
}
