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
      boot-theme
      gpu-nvidia
      astro-a50x
      networking
      tailscale
      wayland
      wooting
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

        # four builds at once, each up to 8 of the 5700X's 16 threads: a project's gate runs its VM
        # tests side by side instead of two at a time, while one big build still gets the 8 it had.
        nix.settings = {
          max-jobs = 4;
          cores = 8;
        };

        # khion is zen 3, so keep the cached generic clang build.
        boot.kernelPackages = pkgs.linuxPackages_cachyos;

        skadi.bootTheme.resolution = {
          width = 2560;
          height = 1440;
        };
      };
  };
}
