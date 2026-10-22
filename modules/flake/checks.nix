{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # build both hosts so a broken config fails the check
      checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        khion = inputs.self.nixosConfigurations.khion.config.system.build.toplevel;
        lumi = inputs.self.nixosConfigurations.lumi.config.system.build.toplevel;
        nvim-project =
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          in
          pkgs.runCommand "nvim-project-check"
            {
              nativeBuildInputs = [
                pkgs.neovim
                pkgs.git
              ];
            }
            ''
              nvim --headless -u NONE -l ${../../tests/nvim-project.lua} \
                ${../..} "$TMPDIR/project-fixture"
              touch "$out"
            '';
        nvim-theme =
          let
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          in
          pkgs.runCommand "nvim-theme-check" { nativeBuildInputs = [ pkgs.neovim ]; } ''
            env XDG_CONFIG_HOME="$TMPDIR/config" \
              nvim --headless -u NONE -l ${../../tests/nvim-theme.lua} \
              ${../..} ${pkgs.vimPlugins.mini-hues}
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
