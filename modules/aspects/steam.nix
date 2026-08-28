{
  den.aspects.steam = {
    # Steam's library lives under ~/.local/share/Steam. Publish the broader
    # ~/.local mount for every user on a host that includes Steam, preserving
    # the existing data layout while moving ownership beside the feature.
    persistence =
      { host, ... }:
      {
        users = builtins.mapAttrs (_: _: {
          directories = [ ".local" ];
        }) host.users;
      };

    nixos =
      { pkgs, ... }:
      {
        programs.steam = {
          enable = true;
          extest.enable = true;
          protontricks.enable = true;
          extraCompatPackages = with pkgs; [
            proton-ge-bin
          ];
        };
      };
  };
}
