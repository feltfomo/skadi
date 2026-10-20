{
  program,
  rootPath,
  ...
}:
{
  den.aspects.fuzzel = program {
    imports = [
      (_: {
        programs.fuzzel = {
          enable = true;
          settings.main = {
            include = "~/.config/fuzzel/themes/reactive";
            namespace = "fuzzel";
            icon-theme = "Papirus-Dark";
            show-actions = "true";
            placeholder = "search...";
            lines = "35";
            width = "75";
            layer = "overlay";
          };
        };
      })
    ];
    directories = [
      {
        src = "${rootPath}/configs/fuzzel";
        dest = ".config/fuzzel";
      }
    ];
    theme = {
      id = "fuzzel";
      output = ".config/fuzzel/themes/reactive";
      # fuzzel reads the included palette each time it opens, so no reload hook is needed
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/fuzzel/themes/reactive";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/fuzzel/themes/caelestia";
      };
    };
  };
}
