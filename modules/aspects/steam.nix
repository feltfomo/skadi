{
  den.aspects.steam = {
    # persisting ~/.steam caused recurring "couldn't set up steam data" failures on khion
    # steam's library stayed under ~/.local/share/Steam instead
    persistence = { host, ... }: {
      users = builtins.mapAttrs (_: _: {
        directories = [ ".local" ];
      }) host.users;
    };

    nixos = { pkgs, ... }: {
      programs = {
        gamemode = {
          enable = true;
          settings = {
            general = {
              desiredgov = "performance";
              softrealtime = "auto";
              inhibit_screensaver = 1;
            };
            custom = {
              start = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
              end = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced";
              script_timeout = 10;
            };
          };
        };

        gamescope = {
          enable = true;
          enableWsi = true;
          capSysNice = true;
        };

        steam = {
          enable = true;
          extest.enable = true;
          protontricks.enable = true;
          extraCompatPackages = with pkgs; [
            proton-ge-bin
            proton-cachyos_x86_64_v3
          ];
        };
      };
    };
  };
}
