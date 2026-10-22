{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      checks =
        inputs.nixpkgs.lib.optionalAttrs
          (
            system == "x86_64-linux"
            && (inputs.self.nixosConfigurations.khion.config.programs.serpantinum.enable or false)
          )
          {
            serpantinum =
              let
                pkgs = inputs.nixpkgs.legacyPackages.${system};
                declarations = inputs.self.nixosConfigurations.khion.config.lexicon.furnish.declarations;
                configFile = builtins.head (
                  builtins.filter (entry: entry.destination == ".config/serpantinum/matugen/config.toml") declarations
                );
                settingsFile = builtins.head (
                  builtins.filter (entry: entry.destination == ".config/serpantinum/settings.json") declarations
                );
                templates = builtins.filter (
                  entry: pkgs.lib.hasPrefix ".config/serpantinum/matugen/templates/" entry.destination
                ) declarations;
                seeds = pkgs.writeText "serpantinum-template-seeds.json" (
                  builtins.toJSON (
                    map (entry: {
                      dest = entry.destination;
                      source = toString entry.source.value;
                    }) templates
                  )
                );
              in
              pkgs.runCommand "serpantinum-check"
                {
                  nativeBuildInputs = [
                    pkgs.imagemagick
                    pkgs.python3
                    pkgs.matugen
                    pkgs.nodejs
                    pkgs.lua
                  ];
                }
                ''
                  python3 ${../../tests/serpantinum.py} \
                    ${inputs.self.packages.${system}.serpantinum}/share/serpantinum \
                    ${configFile.source.value} ${seeds} ${settingsFile.source.value}
                  touch "$out"
                '';
          };
    };
}
