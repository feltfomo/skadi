_: {
  den.aspects.wayland.nixos =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wl-screenrec
        wl-clipboard
        wayland-utils
      ];
    };
}
