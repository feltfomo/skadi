{ ... }:
{
  flake.nixosModules.home =
    { ... }:
    {
      home-manager.users.feltfomo = {
        home.stateVersion = "25.11";
      };
    };
}
