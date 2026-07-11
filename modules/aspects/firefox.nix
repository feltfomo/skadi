{
  program,
  rootPath,
  ...
}:
{
  # firefox is managed by home-manager's programs.firefox so the profile
  # directory is deterministic (~/.config/mozilla/firefox/feltfomo) instead of
  # the old random ~/.config/mozilla/firefox/449sgxzm.default path. that gives
  # noctalia a stable location to template userChrome/userContent into.
  den.aspects.firefox = program {
    imports = [
      (
        { config, ... }:
        {
          programs.firefox = {
            enable = true;
            # opt into the new XDG profile dir now rather than waiting on a
            # home.stateVersion bump, which would silently flip unrelated option
            # defaults too. noctaliaConfig below points at the same path.
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
    templates = [
      {
        name = "userChrome.css";
        templateFile = "${rootPath}/configs/firefox/chrome/userChrome.css";
        subdir = "firefox/";
      }
      {
        name = "userContent.css";
        templateFile = "${rootPath}/configs/firefox/chrome/userContent.css";
        subdir = "firefox/";
      }
    ];
    noctaliaConfig = {
      _fileName = "firefox";
      theme.templates.user.firefox-chrome = {
        input_path = "~/.config/noctalia/templates/firefox/userChrome.css";
        output_path = "~/.config/mozilla/firefox/feltfomo/chrome/userChrome.css";
      };
      theme.templates.user.firefox-content = {
        input_path = "~/.config/noctalia/templates/firefox/userContent.css";
        output_path = "~/.config/mozilla/firefox/feltfomo/chrome/userContent.css";
      };
    };
  };
}
