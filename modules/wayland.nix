{ ... }:
{
  flake.modules.nixos.wayland =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wl-screenrec
        wl-clipboard
        wayland-utils
      ];
    };
}
