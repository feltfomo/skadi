{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      config = inputs.self.nixosConfigurations.khion.config;
      home = config.users.users.feltfomo.home;
      output = "${home}/.local/share/Steam/millennium/themes/Material-Theme/css/main/colors/matugen.css";
      sourceFor =
        destination:
        (lib.findSingle (entry: entry.destination == destination)
          (throw "missing Steam resource ${destination}")
          (throw "duplicate Steam resource ${destination}")
          config.lexicon.furnish.declarations
        ).source.value;
      registrations = {
        noctalia = sourceFor ".config/noctalia/steam.toml";
        dms = sourceFor ".config/matugen/config.toml";
        end4-pc = sourceFor ".config/end4-pc/matugen/config.toml";
        illogical-impulse = sourceFor ".config/illogical-impulse/matugen/config.toml";
        serpantinum = sourceFor ".config/serpantinum/matugen/config.toml";
      };
      contract = pkgs.writeText "steam-theme-contract.json" (
        builtins.toJSON {
          inherit home output registrations;
          manifest = map (entry: {
            destination = entry.filesystemIdentity.destination;
            inherit (entry) representation onConflict;
          }) config.lexicon.furnish.manifestData;
          lumiManifest = map (
            entry: entry.filesystemIdentity.destination
          ) inputs.self.nixosConfigurations.lumi.config.lexicon.furnish.manifestData;
          settings = sourceFor ".config/millennium/config.json";
          caelestiaHook = sourceFor ".config/caelestia/theme-hooks/steam";
          caelestiaTemplate = sourceFor ".config/caelestia/templates/steam-caelestia.css";
          reactiveTemplate = sourceFor ".config/noctalia/templates/steam/reactive.css";
        }
      );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        steam-theme =
          pkgs.runCommand "steam-theme-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.matugen
              ];
            }
            ''
              set -euo pipefail
              python ${../../tests/steam-theme.py} ${contract} ${inputs.steam-material} ${inputs.caelestia.inputs.caelestia-cli}
              touch "$out"
            '';
      };
    };
}
