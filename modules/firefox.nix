{ config, ... }:
{
  flake.modules.nixos.firefox =
    { pkgs, ... }:
    {
      imports = [
        (config.flake.factory.program {
          pkg = pkgs.firefox;
          templates = [
            {
              name = "userChrome.css";
              templateFile = ../configs/firefox/chrome/userChrome.css;
              subdir = "firefox/";
            }
            {
              name = "userContent.css";
              templateFile = ../configs/firefox/chrome/userContent.css;
              subdir = "firefox/";
            }
          ];
        })
      ];
    };
}
