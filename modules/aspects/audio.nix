{ resolveSystem, ... }:
{
  den.aspects.audio =
    { host, ... }:
    {
      # pavucontrol on the real machines only. resolveSystem drops this unit on
      # any host outside the claim, so vm/generic (which also pull base) collapse
      # to {} -- a lean installer-test VM has no use for a volume GUI.
      nixos =
        { pkgs, ... }:
        resolveSystem [
          {
            hosts = [
              "khion"
              "lumi"
            ];
            environment.systemPackages = [ pkgs.pavucontrol ];
          }
        ] { inherit host; };
    };
}
