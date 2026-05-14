{ ... }:
{
  flake.nixosModules.fish =
    { ... }:
    {
      home-manager.users.feltfomo = {
        # install fish for feltfomo
        programs.fish = {
          enable = true;
          # launch terminal with fastfetch
          interactiveShellInit = ''
            fastfetch
          '';
        };
      };
    };
}
