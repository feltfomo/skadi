{ scoped, ... }:
{
  den.aspects.audio =
    { host }:
    let
      for = scoped.for { inherit host; };
    in
    {
      # pavucontrol on the real machines only. the gate does the excluding, so
      # vm/generic (which also pull base) collapse this module to {} -- a lean
      # installer-test VM has no use for a volume GUI.
      nixos =
        for
          {
            hosts = [
              "khion"
              "lumi"
            ];
          }
          (
            { pkgs, ... }:
            {
              environment.systemPackages = [ pkgs.pavucontrol ];
            }
          );
    };
}
