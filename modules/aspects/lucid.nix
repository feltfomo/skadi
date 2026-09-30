{
  inputs,
  program,
  rootPath,
  ...
}:
let
  packageFor =
    pkgs:
    pkgs.callPackage "${rootPath}/pkgs/lucid-shell" {
      quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
  # Skadi's desktop fleet and flake outputs are x86_64-linux. The data walk
  # builds only the patched QML and helpers, not the Quickshell runtime.
  inherit (packageFor inputs.nixpkgs.legacyPackages.x86_64-linux) data;
  stateFiles = {
    "lucidbar/blur.json" = "blur.json";
    "lucidbar/clock_reminders.json" = "clock_reminders.json";
    "lucidbar/mpris_shazam.json" = "mpris_shazam.json";
    "luciddocks/usage.json" = "usage.json";
    "luciddocks/wallpaper.json" = "wallpaper.json";
    "lucidmoji/config.json" = "moji-config.json";
    "lucidmoji/state.json" = "moji-state.json";
    "lucidkeys/state.json" = "keys-state.json";
    "lucidwidgets/widgets.json" = "widgets.json";
  };
in
{
  perSystem = { pkgs, ... }: {
    packages.lucid-shell = packageFor pkgs;
  };

  den.aspects.lucid = program {
    hosts = [
      "khion"
      "lumi"
    ];
    pkg = packageFor;
    nixos = {
      security.polkit.enable = true;
      services.accounts-daemon.enable = true;
      services.upower.enable = true;
    };
    directories = [
      {
        src = "${data}/shell";
        dest = ".config/quickshell/lucid";
      }
      {
        src = "${data}/helpers";
        dest = ".config/lucid";
        exclude = [
          "themes"
          "wallpaper-outputs.conf"
          "set-wallpaper.sh"
        ];
      }
      {
        src = "${data}/helpers/themes";
        dest = ".config/lucid/themes";
        representation = "writable";
        onConflict = "runtime-wins";
      }
    ];
    files =
      builtins.attrValues (
        builtins.mapAttrs (dest: source: {
          src = "${data}/defaults/${source}";
          dest = ".config/quickshell/lucid/${dest}";
          representation = "writable";
          onConflict = "runtime-wins";
        }) stateFiles
      )
      ++ [
        {
          src = "${rootPath}/configs/lucid/prefs.json";
          dest = ".config/quickshell/lucid/lucidprefs/prefs.json";
          representation = "writable";
          onConflict = "runtime-wins";
        }
        {
          src = "${rootPath}/configs/lucid/pinned.json";
          dest = ".config/quickshell/lucid/luciddocks/pinned.json";
          representation = "writable";
          onConflict = "runtime-wins";
        }
        {
          src = "${rootPath}/configs/lucid/wallpaper-outputs.conf";
          dest = ".config/lucid/wallpaper-outputs.conf";
          representation = "writable";
          onConflict = "runtime-wins";
        }
        {
          src = "${data}/helpers/set-wallpaper.sh";
          dest = ".config/hypr/scripts/wallpaper/set-wallpaper.sh";
        }
        {
          src = "${data}/defaults/cava.conf";
          dest = ".config/cava/lucid.conf";
        }
        {
          src = builtins.toFile "lucid-current-theme" "matugen";
          dest = ".cache/current_theme";
          representation = "writable";
          onConflict = "source-wins";
        }
        {
          src = "${data}/helpers/themes/nord/quickshell.json";
          dest = ".cache/quickshell/matugen.json";
          representation = "writable";
          onConflict = "runtime-wins";
        }
      ];
    theme = {
      id = "lucid-shell";
      output = ".cache/quickshell/matugen.json";
      renderers.lucid.source = "${data}/templates/quickshell-colors.json";
    };
  };
}
