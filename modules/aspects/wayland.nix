_: {
  den.aspects.wayland.nixos =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wl-screenrec
        wl-clipboard
        wayland-utils
      ];

      # tell qt/gtk/electron apps to prefer the wayland backend
      environment.variables = {
        QT_QPA_PLATFORM = "wayland;xcb";
        GDK_BACKEND = "wayland,x11,*";
        NIXOS_OZONE_WL = "1";
      };
    };
}
