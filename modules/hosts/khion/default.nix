{ den, inputs, ... }:
{
  flake-file.inputs.chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

  den.hosts.x86_64-linux.khion = {
    users.feltfomo = { };
  };

  # keep feature selection on the aspect so the installer can list and drop it.
  den.aspects.khion = {
    includes = with den.aspects; [
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
      grub
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

        # Use the 5700X's 16 threads without launching many memory-heavy builds at once.
        nix.settings = {
          max-jobs = 2;
          cores = 8;
        };

        # khion is zen 3, so keep the cached generic clang build.
        boot.kernelPackages = pkgs.linuxPackages_cachyos;
      };
  };
}
