{ ... }:
{
  flake.modules.nixos.programs =
    { ... }:
    {
      # enable dconf, neovim, fish, and nix-ld
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
