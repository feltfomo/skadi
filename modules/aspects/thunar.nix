_: {
  # the old thunar.nix was a copy of wayland-packages and never defined thunar.
  # this is the intended file manager.
  den.aspects.thunar.nixos =
    { pkgs, ... }:
    {
      programs.thunar = {
        enable = true;
        plugins = with pkgs; [
          thunar-archive-plugin
          thunar-volman
        ];
      };
      services.gvfs.enable = true;
      services.tumbler.enable = true;
    };
}
