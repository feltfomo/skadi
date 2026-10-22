{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      toml = inputs.lexicon.lib.toml { inherit pkgs; };
      configs = map (name: inputs.self.nixosConfigurations.${name}.config) [
        "khion"
        "lumi"
      ];
      fixtureFor =
        config:
        let
          entries = builtins.filter (
            entry: entry.finalOutput == ".config/herdr/config.toml"
          ) config.lexicon.theme.composition.entries;
          services = lib.filterAttrs (name: _: lib.hasPrefix "lexicon-toml-" name) config.systemd.services;
          service = builtins.head (builtins.attrValues services);
          descriptor = builtins.head (
            builtins.filter (
              entry: lib.hasPrefix "/home/feltfomo/.config/lexicon/toml/" entry.filesystemIdentity.destination
            ) config.lexicon.furnish.manifestData
          );
        in
        assert builtins.length entries == 6;
        assert builtins.length (builtins.attrNames services) == 1;
        assert service.serviceConfig.User == "feltfomo";
        assert builtins.elem "furnish.service" service.after;
        assert builtins.elem "furnish.service" service.requires;
        assert builtins.length service.restartTriggers == 2;
        assert
          !(builtins.any (
            entry: entry.filesystemIdentity.destination == "/home/feltfomo/.config/herdr/config.toml"
          ) config.lexicon.furnish.manifestData);
        {
          descriptor = descriptor.target.path;
          retained = service.restartTriggers;
          palettes = lib.unique (map (entry: entry.source) entries);
        };
      fixtures = pkgs.writeText "herdr-composition-fixtures.json" (
        builtins.toJSON (map fixtureFor configs)
      );
      python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        herdr-composition = pkgs.runCommand "herdr-composition-check" { nativeBuildInputs = [ python ]; } ''
          python ${../../tests/herdr-composition.py} ${toml.package}/bin/lexicon-toml ${fixtures}
          touch "$out"
        '';
      };
    };
}
