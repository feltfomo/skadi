{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # build both hosts so a broken config fails the check
      checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        khion = inputs.self.nixosConfigurations.khion.config.system.build.toplevel;
        lumi = inputs.self.nixosConfigurations.lumi.config.system.build.toplevel;
        lucid-shell =
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            declarations = inputs.self.nixosConfigurations.khion.config.lexicon.furnish.declarations;
            configFile = builtins.head (
              builtins.filter (entry: entry.destination == ".config/lucid/matugen/config.toml") declarations
            );
            templates = builtins.filter (
              entry: pkgs.lib.hasPrefix ".config/lucid/matugen/templates/" entry.destination
            ) declarations;
            seeds = pkgs.writeText "lucid-template-seeds.json" (
              builtins.toJSON (
                map (entry: {
                  dest = entry.destination;
                  source = toString entry.source.value;
                }) templates
              )
            );
          in
          pkgs.runCommand "lucid-shell-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.matugen
                pkgs.lua
                pkgs.imagemagick
              ];
            }
            ''
              python3 ${../../tests/lucid-shell.py} \
                ${inputs.self.packages.${system}.lucid-shell.data} \
                ${configFile.source.value} ${seeds}
              touch "$out"
            '';
        mcp-gateway =
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            mcp = import ../../lib/mcp.nix { inherit (pkgs) lib; };
            gateway = import ../aspects/mcp-host/_gateway.nix {
              inherit pkgs mcp;
              ngrokDomain = "test.invalid";
            };
            headers = pkgs.callPackage ../../pkgs/mcp-gateway-headers { };
          in
          pkgs.runCommand "mcp-gateway-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.caddy
              ];
            }
            ''
              python3 ${../../tests/mcp-gateway.py} ${gateway.gatewayConfig} ${headers}/bin/${headers.name} ${../../configs/pi/mcp-adapter.json}
              touch "$out"
            '';
      };
    };
}
