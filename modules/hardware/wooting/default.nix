_: {
  perSystem = { pkgs, ... }: {
    packages.update-wooting = pkgs.writeShellApplication {
      name = "update-wooting";
      runtimeInputs = [ pkgs.python3 ];
      text = ''
        exec python3 ${./_package/update.py} /etc/skadi/modules/hardware/wooting/_package/release.json
      '';
    };
  };

  den.aspects.wooting = {
    nixos = {
      hardware.wooting.enable = true;
    };

    homeManager =
      { pkgs, ... }:
      let
        bg-service = pkgs.callPackage ./_package { };
      in
      {
        home.packages = [ bg-service ];

        systemd.user.services.wooting-bg-service = {
          Unit = {
            Description = "Wooting Background Service";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "exec";
            ExecStart = "${bg-service}/bin/wooting-bg-service";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}
