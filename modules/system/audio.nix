{ lexicon, ... }:
{
  den.aspects.audio = lexicon {
    # on for only real machines
    nixos =
      { pkgs, ... }:
      [
        {
          hosts = [
            "khion"
            "lumi"
          ];
          value.environment.systemPackages = [
            pkgs.pavucontrol
            # PipeWire's Pulse server does not provide pactl.
            pkgs.pulseaudio
          ];
        }
      ];
  };
}
