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
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        home.activation.obsTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${setup}/bin/app-theme-setup obs
        '';
      };
    theme =
      { pkgs, ... }:
      let
        setup = pkgs.skadi-app-theme-setup;
      in
      {
        id = "obs";
        output = ".config/obs-studio/themes/Reactive.ovt";
        reload = "${setup}/bin/app-theme-setup obs";
        template = ./config/reactive.ovt;
      };
  };
}
