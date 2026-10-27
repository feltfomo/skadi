{
  inputs,
  lexicon,
  ...
}:
let
  themeDirectory = ".local/share/Steam/millennium/themes/Aika";
in
{
  flake-file.inputs = {
    millennium = {
      url = "github:SteamClientHomebrew/Millennium/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a?dir=packages/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    steam-aika = {
      url = "github:hatewxb/Aika/d7722137658a9f89ca8af7dfc563620b3c03a7fe";
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

    furnish = {
      directories = [
        {
          source = "${inputs.steam-aika}";
          destination = themeDirectory;
          exclude = [
            "screenshots"
            ".gitignore"
            "ROADMAP.md"
            "README.md"
            "tools"
          ];
        }
      ];
      files = [
        {
          source = ./config/millennium.json;
          destination = ".config/millennium/config.json";
          # millennium atomically replaces this file when it saves settings.
          representation = "writable";
          onConflict = "source-wins";
        }
      ];
    };
  };
}
