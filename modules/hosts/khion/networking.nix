{ ... }:
{
  flake.nixosModules.khionNetworking =
    { ... }:
    {
      # set hostname and enable networkmanager for khion
      networking = {
        hostName = "khion";
        networkmanager.enable = true;
      };
    };
}
