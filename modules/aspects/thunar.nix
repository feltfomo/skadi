_: {
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
