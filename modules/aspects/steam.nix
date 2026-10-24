{
  inputs,
  lexicon,
  rootPath,
  ...
}:
let
  themeDirectory = ".local/share/Steam/millennium/themes/Material-Theme";
in
{
  flake-file.inputs = {
    millennium = {
      url = "github:SteamClientHomebrew/Millennium/f7a356f6789bc7d23f44bfbcdd95c71f0385cc1a?dir=packages/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    steam-material = {
      url = "github:kuska1/Material-Theme/32b6c127aab294c6f7c79ba7d3a12c717cc67227";
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
          source = "${inputs.steam-material}";
          destination = themeDirectory;
          exclude = [
            ".github"
            ".gitignore"
            "README.md"
            "matugentemplate.css"
            "css/main/colors/matugen.css"
          ];
        }
      ];
      files = [
        {
          source = "${rootPath}/configs/steam/millennium.json";
          destination = ".config/millennium/config.json";
          # millennium atomically replaces this file when it saves settings.
          representation = "writable";
          onConflict = "source-wins";
        }
      ];
    };

    theme = {
      id = "steam";
      output = "${themeDirectory}/css/main/colors/matugen.css";
      renderers = {
        noctalia = {
          source = "${rootPath}/configs/steam/reactive.css";
          sharedWith = [
            "illogical-impulse"
            "serpantinum"
            "end4-pc"
            "dms"
          ];
        };
        caelestia.source = "${rootPath}/configs/steam/caelestia.css";
      };
    };
  };
}
