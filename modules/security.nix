{ ... }:
{
  flake.nixosModules.security =
    { ... }:
    {
      # sudo needs a password
      security.sudo.wheelNeedsPassword = true;
    };
}
