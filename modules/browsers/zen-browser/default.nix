{
  lexicon,
  inputs,
  ...
}:
let
  package =
    pkgs:
    let
      twilight = inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight;
      # Zen ignores SIGPIPE and inotifywait inherits that, so a dead reader wouldn't stop it. stdin
      # closes however Zen ends, including a crash, which makes it the one stop signal.
      paletteWatch = pkgs.writeShellApplication {
        name = "zen-palette-watch";
        runtimeInputs = with pkgs; [ inotify-tools ];
        text = ''
          inotifywait --monitor --event close_write --event moved_to \
            --include '/palette\.css$' "$1" &
          watcher=$!
          read -r _ || true
          kill "$watcher"
        '';
      };
      autoconfig = pkgs.replaceVars ./config/autoconfig.js {
        modules = pkgs.replaceVarsWith {
          src = ./config/palette-reload.sys.mjs;
          dir = "modules";
          replacements.paletteWatch = pkgs.lib.getExe paletteWatch;
        };
      };
      # autoconfig is the only chrome-privileged hook that patches neither omni.ja nor the profile.
      # wrapFirefox's extraPrefs can't deliver it: Zen's executable stays a symlink into the
      # unwrapped package, so Gecko resolves its install directory there and never reads the
      # wrapper's mozilla.cfg.
      unwrapped = twilight.unwrapped.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          libDir="$out/lib/${twilight.unwrapped.libName}"
          chmod u+w "$libDir/defaults/pref"
          install -m 444 ${./config/autoconfig-prefs.js} "$libDir/defaults/pref/skadi.js"
          install -m 444 ${autoconfig} "$libDir/skadi.cfg"
        '';
      });
    in
    import "${inputs.zen-browser}/wrap-zen.nix" pkgs.wrapFirefox unwrapped { };
in
{
  flake-file.inputs.zen-browser = {
    url = "github:0xc000022070/zen-browser-flake";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";
  };

  # a parse error in skadi.cfg stops Zen at startup, and one in the module or a misplaced install only
  # loses reloading without a sign, so neither shows up in a host build.
  perSystem =
    { pkgs, ... }:
    {
      checks.zen-autoconfig =
        pkgs.runCommand "zen-autoconfig"
          {
            nativeBuildInputs = with pkgs; [ nodejs ];
          }
          ''
            install=$(dirname "$(readlink -f ${package pkgs}/bin/.zen-twilight-wrapped)")
            grep -qxF 'pref("general.config.filename", "skadi.cfg");' "$install/defaults/pref/skadi.js"
            cp "$install/skadi.cfg" skadi.cjs
            node --check skadi.cjs
            modules=$(sed -n 's|.*"file://\(.*\)".*|\1|p' skadi.cjs)
            node --check "$modules/palette-reload.sys.mjs"
            touch $out
          '';
    };

  den.aspects.zen-browser = lexicon {
    inherit package;
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
