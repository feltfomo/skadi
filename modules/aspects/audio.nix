{ program, ... }:
{
  den.aspects.audio = program {
    # on for only real machines
    nixos =
      { pkgs, ... }:
      [
        {
          hosts = [
            "khion"
            "lumi"
          ];
          environment.systemPackages = [ pkgs.pavucontrol ];
        }
      ];
  };
}
