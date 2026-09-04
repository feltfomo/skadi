{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.khion = {
    users.feltfomo = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.khion = {
    includes = with den.aspects; [
      base
      cpuid-hypervisor
      docker
      desktop-commander-mcp
      gpu-nvidia
      performance
      networking
      steam
      wayland
      noctalia-greeter
    ];

    nixos =
      { pkgs, ... }:
      {
        imports = [
          inputs.chaotic.nixosModules.default
          inputs.disko.nixosModules.disko
          ./_nixos/disko.nix
          ./_nixos/hardware.nix
        ];

        boot = {
          # khion is zen 3, so keep the cached generic clang build.
          kernelPackages = pkgs.linuxPackages_cachyos;

          # lumi uses systemd-boot and must not inherit khion's grub configuration.
          loader = {
            grub = {
              enable = true;
              device = "nodev";
              efiSupport = true;
            };
            efi.canTouchEfiVariables = true;
          };
        };
      };
  };
}
