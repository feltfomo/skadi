{ ... }:
{
  flake.nixosModules.khionNetworking =
    { ... }:
    {
      networking = {
        hostName = "khion";
        networkmanager.enable = true;
      };
    };
}
