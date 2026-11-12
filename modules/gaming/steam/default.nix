{
  inputs,
  lexicon,
  ...
}:
{
  flake-file.inputs = {
    millennium = {
      url = "github:SteamClientHomebrew/Millennium/dee8e60f689b4f42b04eea0a4f4f063ecd8609aa?dir=packages/nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.millennium-src.follows = "millennium-src";
    };
    # upstream's packaging builds the 64-bit client hook, but its source input still points at a
    # commit from before that code landed; build the packaging's own commit instead.
    millennium-src = {
      url = "github:SteamClientHomebrew/Millennium/dee8e60f689b4f42b04eea0a4f4f063ecd8609aa";
      flake = false;
    };
  };

  den.aspects.steam = lexicon {
    nixos = { pkgs, ... }: [
      {
        value = {
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
              package = inputs.millennium.packages.${pkgs.stdenv.hostPlatform.system}.millennium-steam;
              extest.enable = true;
              protontricks.enable = true;
              extraCompatPackages = with pkgs; [
                proton-cachyos_x86_64_v3
                proton-ge-bin
              ];
            };
          };
        };
      }
    ];
  };
}
