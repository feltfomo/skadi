{ program, ... }: {
  den.aspects.obs = program {
    nixos = { pkgs, ... }: [
      {
        hosts = [ "khion" ];
        programs.obs-studio = {
          enable = true;

          plugins = with pkgs.obs-studio-plugins; [
            obs-pipewire-audio-capture
          ];
        };
      }
    ];
  };
}
