{ ... }:
{
  flake.nixosModules.khionEnvironment =
    { ... }:
    {
      # setting environment variables for khion
      environment = {
        variables = {
          EDITOR = "nvim";
          LIBVA_DRIVER_NAME = "nvidia";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          NVD_BACKEND = "direct";
          GBM_BACKEND = "nvidia-drm";
        };
      };
    };
}
