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
          value.environment.systemPackages = [ pkgs.pavucontrol ];
        }
      ];
  };
}
