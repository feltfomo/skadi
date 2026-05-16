{ ... }:
{
  flake.modules.nixos.wayland-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wl-screenrec
        wl-clipboard
        wayland-utils
      ];
    };
}
