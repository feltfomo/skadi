{ lexicon, ... }:
{
  den.aspects.btop = lexicon {
    homeManager.programs.btop = {
      enable = true;
      settings = {
        color_theme = "reactive";
        theme_background = "false";
        true-color = true;
        rounded-corners = true;
        temp_scale = "fahrenheit";
      };
    };
    furnish.directories = [
      {
        source = ./config;
        destination = ".config/btop";
      }
    ];
    theme = { pkgs, ... }: {
      id = "btop";
      output = ".config/btop/themes/reactive.theme";
      reload = "${pkgs.procps}/bin/pkill -SIGUSR2 -x btop || true";
      template = ./config/reactive.theme;
    };
  };
}
