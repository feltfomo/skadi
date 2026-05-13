{ ... }:
{
  flake.nixosModules.security =
    { ... }:
    {
      security.sudo.wheelNeedsPassword = true;
    };
}
