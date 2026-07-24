{ inputs, den, ... }:
{
  den.aspects.base = {
    includes = with den.aspects; [
      system
      audio
      thunar
      impermanence
      graalvm-oracle-21
      sops
      provision
      installer-tunables
    ];

    nixos = {
      # home-manager + lix modules. hjem is already wired by den; disko is
      # imported per host, next to its disko.devices.
      imports = [
        inputs.home-manager.nixosModules.home-manager
        inputs.lix-module.nixosModules.default
      ];

      # home-manager runs inside the system, sharing pkgs and overlays
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };

      # Assembly installs furnish once, and enablement is deliberately
      # independent of whether any entry is declared: an enabled host with an
      # empty entry set still reconciles, which is what retires entries a later
      # generation stops declaring.
      lexicon.furnish.enable = true;
    };
  };
}
