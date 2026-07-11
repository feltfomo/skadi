{ program, ... }:
{
  den.aspects.audio = program {
    # pavucontrol on the real machines only. the hosts claim drops this unit on
    # any host outside it, so vm/generic (which also pull base) collapse to {}
    # -- a lean installer-test VM has no use for a volume GUI.
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
