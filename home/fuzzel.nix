{ ... }:
{
  programs = {
    fuzzel = {
      enable = true;
      settings = {
        main = {
          include = "~/.config/fuzzel/themes/noctalia";
          namespace = "fuzzel";
          placeholder = "bru";
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
