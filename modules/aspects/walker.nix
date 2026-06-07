{ inputs, ... }:
{
  den.aspects.walker.homeManager = {
    imports = [ inputs.walker.homeManagerModules.walker ];
    # temmplate from wiki havent configured yet
    programs.walker = {
      enable = true;
      runAsService = true;
      config = {
        theme = "default";
        placeholders.default = {
          input = "Search";
          list = "No Results";
        };
        providers.prefixes = [
          {
            provider = "websearch";
            prefix = "+";
          }
          {
            provider = "providerlist";
            prefix = "_";
          }
        ];
        keybinds.quick_activate = [
          "F1"
          "F2"
          "F3"
        ];
      };
    };
  };
}
