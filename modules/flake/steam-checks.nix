{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      config = inputs.self.nixosConfigurations.khion.config;
      home = config.users.users.feltfomo.home;
      themeDirectory = "${home}/.local/share/Steam/millennium/themes/Aika";
      sourceFor =
        destination:
        (lib.findSingle (entry: entry.destination == destination)
          (throw "missing Steam resource ${destination}")
          (throw "duplicate Steam resource ${destination}")
          config.lexicon.furnish.declarations
        ).source.value;
      registrations = {
        dms = sourceFor ".config/matugen/config.toml";
        end4-pc = sourceFor ".config/end4-pc/matugen/config.toml";
        illogical-impulse = sourceFor ".config/illogical-impulse/matugen/config.toml";
        serpantinum = sourceFor ".config/serpantinum/matugen/config.toml";
      };
      contract = pkgs.writeText "steam-theme-contract.json" (
        builtins.toJSON {
          inherit home themeDirectory registrations;
          manifest = map (entry: {
            destination = entry.filesystemIdentity.destination;
            source = entry.target.path;
            inherit (entry) representation onConflict;
          }) config.lexicon.furnish.manifestData;
          lumiManifest = map (
            entry: entry.filesystemIdentity.destination
          ) inputs.self.nixosConfigurations.lumi.config.lexicon.furnish.manifestData;
          settings = sourceFor ".config/millennium/config.json";
        }
      );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        steam-theme =
          pkgs.runCommand "steam-theme-check"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              set -euo pipefail
              python ${../../tests/steam-theme.py} ${contract} ${inputs.steam-aika}
              touch "$out"
            '';
      };
    };
}
