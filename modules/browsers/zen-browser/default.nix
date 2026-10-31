{
  lexicon,
  inputs,
  ...
}:
{
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };

  den.aspects.zen-browser = lexicon {
    package = pkgs: inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight;
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        home.activation.zenBrowserTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup zen-browser
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        id = "zen-browser";
        templates = [
          {
            output = ".config/zen/theme/palette.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            template = ./config/reactive-palette.css;
          }
          {
            subId = "content";
            output = ".config/zen/theme/userContent.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            template = ./config/theme/userContent.css;
          }
          {
            subId = "chrome";
            output = ".config/zen/theme/userChrome.css";
            reload = "${setup}/bin/app-theme-setup zen-browser";
            template = ./config/theme/userChrome.css;
          }
        ];
      };

    furnish.files =
      map
        (name: {
          source = ./config/theme + "/${name}.css";
          destination = ".config/zen/theme/${name}.css";
          representation = "writable";
          onConflict = "source-wins";
        })
        [
          "materials"
          "content"
          "chrome"
          "panels"
          "urlbar"
          "tabs"
        ];
  };
}
