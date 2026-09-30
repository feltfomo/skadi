{
  inputs,
  program,
  ...
}:
{
  flake-file.inputs.pi-extensions = {
    url = "github:feltfomo/pi-extensions";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      home-manager.follows = "home-manager";
    };
  };

  den.aspects.pi = program {
    pkg =
      pkgs:
      let
        pi = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;
        headers = pkgs.callPackage ../../pkgs/mcp-gateway-headers { };
      in
      pkgs.symlinkJoin {
        name = "pi-mcp-${pi.version}";
        inherit (pi) pname version meta;
        paths = [ pi ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/pi" \
            --set PI_MCP_CONFIG_MODE exclusive \
            --prefix PATH : ${headers}/bin
        '';
      };
    files = [
      {
        src = ../../configs/pi/AGENTS.md;
        dest = ".pi/agent/AGENTS.md";
        onConflict = "source-wins";
      }
      {
        src = ../../configs/pi/mcp-adapter.json;
        dest = ".pi/agent/mcp-adapter.json";
        onConflict = "source-wins";
      }
    ];
    imports = [
      inputs.pi-extensions.homeManagerModules.status-lines
      (
        { config, pkgs, ... }:
        let
          extensions = pkgs.callPackage ../../pkgs/pi-community-extensions { };
          extensionDir = "${config.programs.pi-coding-agent.configDir}/extensions";
        in
        {
          programs.pi-coding-agent.extensions.status-lines.enable = true;
          home.packages = [
            extensions
            (pkgs.callPackage ../../pkgs/mcp-gateway-headers { })
            pkgs.nodejs_24
            pkgs.keyutils
          ];
          home.file."${extensionDir}/pi-web-access.ts".text = ''
            export { default } from "${extensions}/node_modules/pi-web-access/dist/index.js";
          '';
          home.file."${extensionDir}/pi-mcp-adapter.ts".text = ''
            export { default } from "${extensions}/node_modules/pi-mcp-adapter/index.ts";
          '';
        }
      )
    ];
  };
}
