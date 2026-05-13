{ ... }:
{
  flake.nixosModules.fuzzel =
    { ... }:
    {
      home-manager.users.feltfomo.programs.fuzzel = {
        enable = true;
        settings = {
          main = {
            include = "~/.config/fuzzel/themes/noctalia";
            namespace = "fuzzel";
            placeholder = "bru";
            icon-theme = "Papirus-Dark";
            message = "Skadi - App Launcher";
            show-actions = "true";
            lines = "35";
            width = "75";
            layer = "overlay";
          };
        };
      };
    };
}
