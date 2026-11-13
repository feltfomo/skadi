{ lexicon, ... }:
{
  den.aspects.audio = lexicon {
    # on for only real machines
    hosts = [
      "khion"
      "lumi"
    ];
    nixos =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          pkgs.pavucontrol
          # PipeWire's Pulse server does not provide pactl.
          pkgs.pulseaudio
        ];
      };
  };
}
