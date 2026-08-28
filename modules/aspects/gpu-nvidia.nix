{
  den.aspects.gpu-nvidia.nixos =
    { config, pkgs, ... }:
    {
      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        modesetting.enable = true;
        open = true; # required for the rtx 4060 (ada) on current drivers
        package =
          let
            cachyosNvidia = config.boot.kernelPackages.nvidiaPackages.cachyos;
          in
          cachyosNvidia.overrideAttrs (old: {
            passthru = old.passthru // {
              # strip external modules before the cachyos kernel compresses them
              open = old.passthru.open.overrideAttrs (openOld: {
                installFlags = (openOld.installFlags or [ ]) ++ [ "INSTALL_MOD_STRIP=1" ];
              });
            };
          });
        nvidiaSettings = true;
        nvidiaPersistenced = true;
        powerManagement = {
          enable = true;
          finegrained = false;
        };
      };

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          nvidia-vaapi-driver
        ];
      };

      boot.kernelParams = [
        # nvidia drm fbdev keeps the early wayland handoff out of simpledrm
        "nvidia-drm.fbdev=1"
        "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
        "nvidia.NVreg_TemporaryFilePath=/var/tmp"
      ];

      boot.kernelModules = [ "nvidia-uvm" ]; # cuda

      # steer the userspace gl/va/gbm stack at the nvidia driver
      environment.variables = {
        LIBVA_DRIVER_NAME = "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        NVD_BACKEND = "direct";
        GBM_BACKEND = "nvidia-drm";
      };

      # coolbits enables the fan-control knob the service below drives
      environment.etc."X11/xorg.conf.d/20-nvidia.conf".text = ''
        Section "Device"
        Identifier "NVIDIA Card"
        Driver "nvidia"
        Option "Coolbits" "4"
        EndSection
      '';

      systemd.services.nvidia-fan-control = {
        description = "NVIDIA Custom Fan Curve";
        wantedBy = [ "multi-user.target" ];
        after = [ "multi-user.target" ];
        path = [ (pkgs.python3.withPackages (ps: [ ps.nvidia-ml-py ])) ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          User = "root";
          ExecStart = pkgs.writeShellScript "nvidia-fan-control" ''
            python3 ${pkgs.writeText "fan-control.py" ''
              import pynvml
              import time
              pynvml.nvmlInit()
              handle = pynvml.nvmlDeviceGetHandleByIndex(0)
              while True:
                  temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                  if temp < 50:
                      speed = 30
                  elif temp < 60:
                      speed = 50
                  elif temp < 70:
                      speed = 65
                  elif temp < 80:
                      speed = 80
                  else:
                      speed = 100
                  pynvml.nvmlDeviceSetFanSpeed_v2(handle, 0, speed)
                  time.sleep(5)
            ''}
          '';
        };
      };

      environment.systemPackages = with pkgs; [
        vulkan-tools
        vulkan-loader
        vulkan-validation-layers
      ];

      # setting VK_DRIVER_FILES or VK_ICD_FILENAMES globally breaks 32-bit vulkan.
      # the loader finds both opengl driver trees automatically.
    };
}
