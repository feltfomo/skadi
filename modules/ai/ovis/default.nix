{ inputs, den, ... }:
let
  cliFor =
    pkgs:
    pkgs.writeShellApplication {
      name = "ovis";
      runtimeInputs = [ pkgs.systemd ];
      text = ''
        exec ${pkgs.lib.getExe pkgs.nushell} --no-config-file "${./ovis.nu}" "$@"
      '';
    };
  ovisFor =
    pkgs:
    pkgs.callPackage ./_package {
      bun2nixLib = (inputs.llm-agents.inputs.bun2nix.overlays.default pkgs pkgs).bun2nix;
      herdr = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
    };
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        ovis = ovisFor pkgs;
        ovis-cli = cliFor pkgs;
      };
    };

  den.aspects.ovis = {
    includes = [ den.aspects.herdr ];
    homeManager =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      let
        ovis = ovisFor pkgs;
        cli = cliFor pkgs;
        url = "http://127.0.0.1:7317";
        launcher = pkgs.writeShellApplication {
          name = "ovis-webapp";
          text = ''
            ${lib.getExe cli} on
            exec ${lib.getExe pkgs.brave-origin} --class=ovis --app=${url} "$@"
          '';
        };
      in
      {
        home.packages = [
          launcher
          cli
        ];

        systemd.user.services.ovis = {
          Unit.Description = "Ovis local Herdr web client";
          Service = {
            Type = "exec";
            ExecStart = lib.getExe ovis;
            ExecStartPost = "${lib.getExe pkgs.curl} --fail --silent --show-error --retry 30 --retry-delay 1 --retry-connrefused --retry-max-time 30 --max-time 2 ${url}/api/health";
            Restart = "on-failure";
            RestartSec = 2;
            TimeoutStartSec = 40;
            StateDirectory = "ovis";
            CacheDirectory = "ovis";
            Environment = [
              "BUN_RUNTIME_TRANSPILER_CACHE_PATH=${config.xdg.cacheHome}/ovis/bun"
              "HERDR_WEB_STATE_DIR=${config.xdg.stateHome}/ovis"
              "HERDR_WEB_TELEMETRY=0"
              "HOST=127.0.0.1"
              "PORT=7317"
            ];
          };
        };

        xdg.desktopEntries.ovis = {
          name = "Ovis";
          genericName = "Herdr web client";
          exec = lib.getExe launcher;
          icon = "${ovis}/share/icons/hicolor/512x512/apps/ovis.png";
          terminal = false;
          categories = [ "Development" ];
          settings.StartupWMClass = "ovis";
        };
      };
  };
}
