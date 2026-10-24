{
  lexicon,
  rootPath,
  ...
}:
{
  # kitty claims no host or user, so it is globally owned.
  den.aspects.kitty = lexicon {
    package = pkgs: pkgs.kitty;
    furnish.directories = [
      {
        source = "${rootPath}/configs/kitty";
        destination = ".config/kitty";
      }
    ];
    theme = {
      id = "kitty";
      output = ".config/kitty/themes/reactive.conf";
      reload = "pkill -SIGUSR1 kitty";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/kitty/themes/reactive.conf";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/kitty/themes/caelestia.conf";
      };
    };
  };
}
