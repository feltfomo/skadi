_: {
  den.aspects.wooting = {
    nixos = {
      hardware.wooting.enable = true;
    };

    # wooting-bg-service
    homeManager =
      { pkgs, ... }:
      let
        bg-service = pkgs.callPackage ../../pkgs/wooting-bg-service { };
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
