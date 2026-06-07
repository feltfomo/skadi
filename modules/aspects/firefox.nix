{
  lib,
  rootPath,
  ...
}:
let
  program = import ../_lib/program.nix { inherit lib; };
in
{
  den.aspects.firefox = program {
    pkg = pkgs: pkgs.firefox;
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
        output_path = "~/.config/mozilla/firefox/449sgxzm.default/chrome/userChrome.css";
      };
      theme.templates.user.firefox-content = {
        input_path = "~/.config/noctalia/templates/firefox/userContent.css";
        output_path = "~/.config/mozilla/firefox/449sgxzm.default/chrome/userContent.css";
      };
    };
  };
}
