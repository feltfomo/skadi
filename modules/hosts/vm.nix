# throwaway vm host for testing the installer end-to-end in qemu without touching
# real hardware. same disko/luks/impermanence/sops flow as the real hosts, but the
# disk is /dev/vda (virtio) and there's no nvidia/steam/gpu.
# install from the ISO with:  skadi-install vm
{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.vm = {
    users.feltfomo = { };
  };

  den.aspects.vm = {
    includes = [
      den.aspects.base # system + impermanence + sops + graalvm + thunar
      den.aspects.notion-sync # exercises the notion-token secret + mappings
    ];

    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_vm/disko.nix
      ./_vm/hardware.nix
      ./_vm/networking.nix
    ];
  };
}
