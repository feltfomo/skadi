{
  den.aspects.grub.nixos =
    { pkgs, ... }:
    let
      theme = pkgs.callPackage ./_elegant-theme.nix { };
    in
    {
      boot.loader = {
        grub = {
          enable = true;
          device = "nodev";
          efiSupport = true;
          inherit theme;
          splashImage = "${theme}/background.jpg";
          gfxmodeEfi = "1920x1080,auto";
          gfxmodeBios = "1920x1080,auto";
        };
        efi.canTouchEfiVariables = true;
      };
    };
}
