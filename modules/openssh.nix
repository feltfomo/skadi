{ ... }:
{
  flake.nixosModules.openssh =
    { ... }:
    {
      services.openssh = {
        enable = true;
      };
    };
}
