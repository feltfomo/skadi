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
      contract = pkgs.writeText "desktop-theme-contract.json" (
        builtins.toJSON {
          home = config.users.users.feltfomo.home;
          boot = {
            inherit (config.boot.loader.grub) splashImage theme;
          };
          gtkTheme = config.home-manager.users.feltfomo.gtk.theme.name;
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
