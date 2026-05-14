{ ... }:
{
  flake.nixosModules.nyx =
    { ... }:
    {
      # enable and configure nyx
      home-manager.users.feltfomo = {
        programs.nix-your-shell = {
          enable = true;
          enableFishIntegration = true;
          nix-output-monitor.enable = true;
        };
      };
    };
}
