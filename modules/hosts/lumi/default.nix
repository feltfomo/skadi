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

    # grandpa logs in without picking anything. the greeter remembers one last session for every
    # user, so plasma is pinned and the other sessions are picked by hand.
    nixos.services.displayManager.noctalia-greeter.settings = {
      session.default = "Plasma (Wayland)";
      user.default = "grandpa";
    };

    # one large build, such as a whole cargo workspace, gets all four of the N95's cores; a fixed
    # share per build left half of them idle whenever only one build ran.
    nixos.nix.settings = {
      max-jobs = 2;
      cores = 0;
    };

    # disko's nixos module must sit with the disko.devices it enables
    nixos.imports = [
      inputs.disko.nixosModules.disko
      ./_nixos/hardware.nix
      ./_nixos/disko.nix
    ];
  };
}
