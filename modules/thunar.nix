{ ... }:
{
  flake.nixosModules.thunar =
    { pkgs, ... }:
    {
      programs = {
        # file manager with plugins
        thunar = {
          enable = true;
          plugins = with pkgs; [
            thunar-archive-plugin
            thunar-volman
          ];
        };

        # needed for thunar settings persistence
        xfconf.enable = true;
      };
      services = {
        # virtual filesystem support for thunar
        gvfs.enable = true;

        # thumbnail generation
        tumbler.enable = true;
      };
    };
}
