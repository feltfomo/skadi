{ ... }:
{
  flake.nixosModules.fish =
    { ... }:
    {
      home-manager.users.feltfomo = {
        programs.fish = {
          enable = true;
          interactiveShellInit = ''
            fastfetch
          '';
        };
      };
    };
}
