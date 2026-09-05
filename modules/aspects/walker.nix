{ inputs, ... }:
{
  flake-file = {
    inputs = {
      elephant = {
        url = "github:abenz1267/elephant";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      walker = {
        url = "github:abenz1267/walker";
        inputs.nixpkgs.follows = "nixpkgs";
        inputs.elephant.follows = "elephant";
      };
    };
    nixConfig = {
      extra-substituters = [
        "https://walker.cachix.org"
        "https://walker-git.cachix.org"
      ];
      extra-trusted-public-keys = [
        "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
        "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      ];
    };
  };

  den.aspects.walker.homeManager = {
    imports = [ inputs.walker.homeManagerModules.walker ];
    # template from wiki, haven't configured yet
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
