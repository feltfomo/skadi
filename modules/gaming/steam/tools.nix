{
  den.aspects.steam-tools.homeManager =
    {
      pkgs,
      lib,
      osConfig,
      ...
    }:
    lib.mkIf osConfig.programs.steam.enable {
      home.packages = [ pkgs.sgdboop ];

      # the wiped root removed ~/.steam before the steam wrapper's repair step
      # repair then failed while creating ~/.steam/steam with "no such file or directory"
      home.activation.steamSymlinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/.steam"
        run ln -sfn "$HOME/.local/share/Steam" "$HOME/.steam/steam"
        run ln -sfn "$HOME/.local/share/Steam" "$HOME/.steam/root"
      '';

    };
}
