{ ... }:
{
  flake.nixosModules.programs =
    { ... }:
    {
      programs = {
        dconf.enable = true;
        neovim = {
          enable = true;
          defaultEditor = true;
        };
        fish.enable = true;
        nix-ld.enable = true;
      };
    };
}
