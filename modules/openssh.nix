{ ... }:
{
  flake.nixosModules.openssh =
    { ... }:
    {
      # enable openssh
      services.openssh = {
        enable = true;
      };
    };
}
