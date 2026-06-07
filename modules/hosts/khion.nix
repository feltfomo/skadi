{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.khion = {
    gpu = "nvidia";

    users.feltfomo = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.khion = {
    includes = [
      den.aspects.base
      den.aspects.gpu-nvidia
      den.aspects.steam
      den.aspects.walker
      den.aspects.firefox
      den.aspects.wayland
      den.aspects.qt-hm
    ];

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_khion/disko.nix
      ./_khion/hardware.nix
      ./_khion/networking.nix
      ./_khion/environment.nix
    ];
  };
}
