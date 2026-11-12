# steam's Millennium theme: palette materials, recolor.js and the client windows it applies to, and
# the store and community pages the web sheets theme. theme.md explains how the layers fit together.
{ lexicon, ... }:
let
  name = "Skadi";
  directory = ".local/share/Steam/millennium/themes/${name}";
  palette = ./config/palette.css;
  # client windows; a pattern is a window-title regex or a root class.
  windows = [
    "^Steam$"
    ".ModalDialogPopup"
    ".friendsui-container"
    ".ContextMenuPopup"
    "Menu$"
    "Supernav$"
    "^notificationtoasts_"
    ".DesktopToastContainer"
    "^Sign in to Steam$"
  ];
  # web pages, each themed by theme/web/<name>.scss. millennium matches url against the whole page
  # url, so a page left out (checkout, help, the cart) stays native.
  pages = [
    {
      name = "store-front";
      url = ''https://store\.steampowered\.com/?(\?.*)?'';
    }
    {
      name = "app-page";
      url = ''https://store\.steampowered\.com/app/[0-9]+(/.*)?'';
    }
    {
      name = "community";
      url = ''https://steamcommunity\.com/?(\?.*)?'';
    }
  ];
  sheetOf = page: "web/${page.name}.css";
  skin = builtins.toJSON {
    inherit name;
    author = "feltfomo";
    description = "Steam in the Skadi palette";
    version = "1.0.0";
    # a patch carries one stylesheet, so the palette gets its own. recolor.js refreshes it in client
    # windows; steam's web pages block theme scripts, so they pick up a new palette on their next load.
    Patches =
      builtins.concatMap (pattern: [
        {
          MatchRegexString = pattern;
          TargetCss = "palette.css";
        }
        {
          MatchRegexString = pattern;
          TargetCss = "theme.css";
          TargetJs = "recolor.js";
        }
      ]) windows
      ++ builtins.concatMap (page: [
        {
          MatchRegexString = page.url;
          TargetCss = "palette.css";
        }
        {
          MatchRegexString = page.url;
          TargetCss = sheetOf page;
        }
      ]) pages;
  };
  files = [
    "skin.json"
    "theme.css"
    "recolor.js"
  ]
  ++ map sheetOf pages;
  themeFor =
    pkgs: extra:
    pkgs.callPackage ./_theme-package.nix (
      {
        inherit skin palette files;
        pages = map (page: page.name) pages;
      }
      // extra
    );
in
{
  perSystem =
    { pkgs, self', ... }:
    {
      checks.steam-theme = themeFor pkgs { inherit (self'.packages) skadi-theme-design; };
    };

  den.aspects.steam-theme = lexicon {
    furnish.files =
      { pkgs, ... }:
      map (file: {
        source = "${themeFor pkgs { }}/${file}";
        destination = "${directory}/${file}";
      }) files
      ++ [
        {
          source = ./config/millennium.json;
          destination = ".config/millennium/config.json";
          # millennium atomically replaces this file when it saves settings.
          representation = "writable";
          onConflict = "source-wins";
        }
      ];
    theme = _: {
      id = "steam";
      templates = [
        {
          output = "${directory}/palette.css";
          template = palette;
        }
      ];
    };
  };
}
