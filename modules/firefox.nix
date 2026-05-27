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
          noctaliaConfig = {
            _fileName = "firefox";
            theme.templates.user.firefox-chrome = {
              input_path = "~/.config/noctalia/templates/firefox/userChrome.css";
              output_path = "~/.config/mozilla/firefox/449sgxzm.default/chrome/userChrome.css";
            };
            theme.templates.user.firefox-content = {
              input_path = "~/.config/noctalia/templates/firefox/userContent.css";
              output_path = "~/.config/mozilla/firefox/449sgxzm.default/chrome/userContent.css";
            };
          };
        })
      ];
    };
}
