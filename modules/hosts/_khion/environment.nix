_: {
  # setting environment variables for khion
  environment = {
    variables = {
      # EDITOR is set globally via programs.neovim.defaultEditor in system.nix
      # nvidia
      LIBVA_DRIVER_NAME = "nvidia";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      NVD_BACKEND = "direct";
      GBM_BACKEND = "nvidia-drm";
      # wayland
      QT_QPA_PLATFORM = "wayland;xcb";
      GDK_BACKEND = "wayland,x11,*";
      NIXOS_OZONE_WL = "1";
    };
  };
}
