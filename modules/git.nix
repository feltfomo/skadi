{ ... }:
{
  flake.nixosModules.git =
    { ... }:
    {
      home-manager.users.feltfomo = {
        programs.git = {
          enable = true;
          settings.user = {
            name = "feltfomo";
            email = "241195017+feltfomo@users.noreply.github.com";
          };
        };
      };
    };
}
