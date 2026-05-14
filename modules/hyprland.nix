{ rootPath, ... }:
{
  flake.nixosModules.hyprland =
    { ... }:
    {
      # enable hyprland
      programs = {
        hyprland = {
          enable = true;
        };
      };

      hjem.users.feltfomo = {
        files = {
          ".config/hypr".source = "${rootPath}/configs/hypr";
        };
      };
    };
}
