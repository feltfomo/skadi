{ config, pkgs, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
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
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_TemporaryFilePath=/var/tmp"
    "nowatchdog"
  ];
  boot.kernelModules = [ "nvidia-uvm" ];
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
  environment.variables.VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
}
