{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.khion = {
    users.feltfomo = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.khion = {
    includes = [
      den.aspects.base
      den.aspects.docker
      den.aspects.gpu-nvidia
      den.aspects.hermes
      den.aspects.notion-sync
      den.aspects.steam
      den.aspects.wayland
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
