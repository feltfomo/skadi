{ lexicon, ... }: {
  den.aspects.obs = lexicon {
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
  };
}
