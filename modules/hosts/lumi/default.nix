{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.lumi = {
    users.feltfomo = { };
    users.grandpa = { };
  };

  # keep feature selection on the aspect so the installer can list and drop it.
  den.aspects.lumi = {
    includes = with den.aspects; [
      noctalia-greeter
      boot-theme
      networking
      tailscale
      wayland
      plasma
      tablet
      grub
      base
    ];

    # fill the N95's 4 cores with two builds at once, matching khion's two-job split.
    nixos.nix.settings = {
      max-jobs = 2;
      cores = 2;
    };

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_nixos/hardware.nix
      ./_nixos/disko.nix
    ];
  };
}
