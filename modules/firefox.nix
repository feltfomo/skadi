{ config, ... }:
{
  flake.modules.nixos.firefox =
    { pkgs, ... }:
    {
      imports = [
        (config.flake.factory.noctaliaTemplate {
          name = "userChrome.css";
          templateFile = ../configs/firefox/chrome/userChrome.css;
          subdir = "firefox/";
        })
        (config.flake.factory.noctaliaTemplate {
          name = "userContent.css";
          templateFile = ../configs/firefox/chrome/userContent.css;
          subdir = "firefox/";
        })
      ];
      home-manager.users.feltfomo =
        { ... }:
        {
          home.packages = with pkgs; [ firefox ];
        };
    };
}
