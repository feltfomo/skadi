{ den, inputs, ... }:
{
  flake-file.inputs.chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

  den.hosts.x86_64-linux.khion = {
    users.feltfomo = { };
  };

  # den activates the host aspect, so feature includes go here. includes on
  # the host entity are inert freeform metadata.
  den.aspects.khion = {
    includes = with den.aspects; [
      desktop-commander-mcp
      cpuid-hypervisor
      noctalia-greeter
      performance
      gpu-nvidia
      networking
      tailscale
      wayland
      wooting
      docker
      tablet
      steam
      base
    ];

    nixos =
      { pkgs, ... }:
      {
        imports = [
          inputs.chaotic.nixosModules.default
          inputs.disko.nixosModules.disko
          ./_nixos/hardware.nix
          ./_nixos/disko.nix
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
