{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # build both hosts so a broken config fails the check
      checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        khion = inputs.self.nixosConfigurations.khion.config.system.build.toplevel;
        lumi = inputs.self.nixosConfigurations.lumi.config.system.build.toplevel;
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
                pkgs.python3
                pkgs.matugen
                pkgs.lua
                pkgs.imagemagick
                pkgs.nodejs
              ];
            }
            ''
              python3 ${../../tests/serpantinum.py} \
                ${inputs.self.packages.${system}.serpantinum}/share/serpantinum \
                ${configFile.source.value} ${seeds} ${settingsFile.source.value}
              touch "$out"
            '';
        nvim-theme-reload =
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          in
          pkgs.runCommand "nvim-theme-reload-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.neovim
              ];
            }
            ''
              python3 ${../../tests/nvim-theme-reload.py} \
                nvim --headless -u NONE -l ${../../configs/nvim/reload-theme.lua}
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
