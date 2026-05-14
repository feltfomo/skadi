{ ... }:
{
  flake.nixosModules.lumiNetworking =
    { ... }:
    {
      # set hostname and enable networkmanager for lumi
      networking = {
        hostName = "lumi";
        networkmanager.enable = true;
      };
    };
}
