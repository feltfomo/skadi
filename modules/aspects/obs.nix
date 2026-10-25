{ lexicon, ... }: {
  den.aspects.obs = lexicon {
    hosts = [ "khion" ];
    nixos = { pkgs, ... }: [
      {
        hosts = [ "khion" ];
        value.programs.obs-studio = {
          enable = true;

          plugins = with pkgs.obs-studio-plugins; [
            obs-pipewire-audio-capture
          ];
        };
      }
    ];
    homeManager =
      { pkgs, lib, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        home.activation.obsTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup obs
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = import ../../lib/theme-setup.nix { inherit pkgs; };
      in
      {
        id = "obs";
        output = ".config/obs-studio/themes/Reactive.ovt";
        reload = "${setup}/bin/app-theme-setup obs";
        renderers = {
          noctalia = {
            source = ../../configs/obs/reactive.ovt;
            sharedWith = [
              "illogical-impulse"
              "serpantinum"
              "end4-pc"
              "dms"
            ];
          };
          caelestia.source = ../../configs/obs/caelestia.ovt;
        };
      };
  };
}
