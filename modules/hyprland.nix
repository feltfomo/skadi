{ ... }:
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
    };
}
