{
  program,
  rootPath,
  ...
}:
{
  # firefox is managed by home-manager's programs.firefox so the profile
  # directory is deterministic (~/.config/mozilla/firefox/feltfomo) instead of
  # the old random ~/.config/mozilla/firefox/449sgxzm.default path.
  den.aspects.firefox = program {
    imports = [
      (
        { config, ... }:
        {
          programs.firefox = {
            enable = true;
            # opt into the new XDG profile dir now rather than waiting on a
            # home.stateVersion bump, which would silently flip unrelated option
            # defaults too.
            configPath = "${config.xdg.configHome}/mozilla/firefox";
            profiles.feltfomo = {
              id = 0;
              isDefault = true;
              # required for userChrome.css / userContent.css to take effect
              settings."toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            };
          };
        }
      )
    ];
    theme = {
      id = "firefox";
      templates = [
        {
          subId = "chrome";
          renderers = {
            noctalia = {
              source = "${rootPath}/configs/firefox/chrome/userChrome.css";
              output = ".config/mozilla/firefox/feltfomo/chrome/userChrome.css";
            };
            dms = {
              source = "${rootPath}/configs/firefox/chrome/userChrome.css";
              output = ".config/mozilla/firefox/feltfomo/chrome/userChrome.css";
            };
            caelestia = {
              source = "${rootPath}/configs/firefox/chrome/caelestia-userChrome.css";
              output = ".config/mozilla/firefox/feltfomo/chrome/userChrome.css";
              placedAs = "userChrome.css";
            };
          };
        }
        {
          subId = "content";
          renderers = {
            noctalia = {
              source = "${rootPath}/configs/firefox/chrome/userContent.css";
              output = ".config/mozilla/firefox/feltfomo/chrome/userContent.css";
            };
            dms = {
              source = "${rootPath}/configs/firefox/chrome/userContent.css";
              output = ".config/mozilla/firefox/feltfomo/chrome/userContent.css";
            };
            caelestia = {
              source = "${rootPath}/configs/firefox/chrome/caelestia-userContent.css";
              output = ".config/mozilla/firefox/feltfomo/chrome/userContent.css";
              placedAs = "userContent.css";
            };
          };
        }
      ];
    };
  };
}
