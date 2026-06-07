{ inputs, den, ... }:
{
  den.aspects.base = {
    includes = [
      den.aspects.system
      den.aspects.thunar
      den.aspects.impermanence
      den.aspects.graalvm-oracle-21
    ];

    nixos = {
      # home-manager module for the homeManager class, lix as the nix impl.
      # hjem is wired by den, so importing its module here declares hjem-lib
      # twice. disko is imported per host, next to its disko.devices.
      imports = [
        inputs.home-manager.nixosModules.home-manager
        inputs.lix-module.nixosModules.default
      ];

      # home-manager runs inside the system, sharing pkgs and overlays
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };
    };
  };
}
