{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      config = inputs.self.nixosConfigurations.khion.config;
      sourceFor =
        destination:
        (lib.findSingle (entry: entry.destination == destination)
          (throw "missing theme resource ${destination}")
          (throw "duplicate theme resource ${destination}")
          config.lexicon.furnish.declarations
        ).source.value;
      python = pkgs.python3.withPackages (packages: [
        packages.coloraide
        packages.tomlkit
      ]);
      compositionSources = map (entry: entry.source.value) (
        builtins.filter (
          entry: lib.hasPrefix ".config/lexicon/toml/" entry.destination
        ) config.lexicon.furnish.declarations
      );
      nativeThemePython = pkgs.python3.withPackages (packages: [
        packages.pygobject3
        packages.pycairo
        packages.pyqt6
      ]);
      gtkTheme = pkgs.callPackage ../../pkgs/skadi-gtk-theme { };
      qtTheme = pkgs.callPackage ../../pkgs/skadi-qt-theme { };
      contract = pkgs.writeText "desktop-theme-contract.json" (
        builtins.toJSON {
          home = config.users.users.feltfomo.home;
          boot = {
            inherit (config.boot.loader.grub) splashImage theme;
          };
          gtkTheme = config.home-manager.users.feltfomo.gtk.theme.name;
          qtStyle = config.home-manager.users.feltfomo.qt.style.name;
          qtTheme = config.home-manager.users.feltfomo.qt.kvantum.settings.General.theme;
          starship = config.home-manager.users.feltfomo.programs.starship.enable;
          registrations = {
            illogical-impulse = sourceFor ".config/illogical-impulse/matugen/config.toml";
            serpantinum = sourceFor ".config/serpantinum/matugen/config.toml";
            end4-pc = sourceFor ".config/end4-pc/matugen/config.toml";
            dms = sourceFor ".config/matugen/config.toml";
          };
          manifest = map (entry: {
            destination = entry.filesystemIdentity.destination;
            source = entry.target.path;
          }) config.lexicon.furnish.manifestData;
          lumiManifest = map (
            entry: entry.filesystemIdentity.destination
          ) inputs.self.nixosConfigurations.lumi.config.lexicon.furnish.manifestData;
        }
      );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        native-themes =
          pkgs.runCommand "native-themes-check"
            {
              nativeBuildInputs = [
                nativeThemePython
                pkgs.gobject-introspection
                pkgs.gtk3
                pkgs.gtk4
                pkgs.libadwaita
                pkgs.xvfb-run
                pkgs.matugen
                pkgs.dbus
              ];
              GDK_PIXBUF_MODULE_FILE = "${pkgs.librsvg}/${pkgs.gdk-pixbuf.binaryDir}/loaders.cache";
              GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
              GSETTINGS_BACKEND = "memory";
              XDG_DATA_DIRS = lib.makeSearchPath "share" [
                gtkTheme
                pkgs.adwaita-icon-theme
                pkgs.shared-mime-info
              ];
              FONTCONFIG_FILE = pkgs.makeFontsConf {
                fontDirectories = [ pkgs.maple-mono.NF ];
              };
            }
            ''
              set -euo pipefail
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export XDG_RUNTIME_DIR="$TMPDIR/runtime"
              mkdir -p "$XDG_RUNTIME_DIR"
              chmod 700 "$XDG_RUNTIME_DIR"
              dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
                xvfb-run -a -s "-screen 0 1280x1024x24" \
                python ${../../tests/native-themes.py} ${../..} ${gtkTheme} ${qtTheme} "$out" \
                ${pkgs.qt6Packages.qtstyleplugin-kvantum}/${pkgs.qt6Packages.qtbase.qtPluginPrefix}
            '';
        desktop-themes =
          pkgs.runCommand "desktop-themes-check"
            {
              inherit compositionSources;
              nativeBuildInputs = [
                pkgs.starship
                pkgs.matugen
                python
                pkgs.git
              ];
            }
            ''
              set -euo pipefail
              python ${../../tests/app-theme-setup.py} ${../../scripts/app-theme-setup.py}
              python ${../../tests/desktop-themes.py} ${contract} ${../..}
              touch "$out"
            '';
      };
    };
}
