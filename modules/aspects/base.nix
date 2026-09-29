{
  inputs,
  den,
  ...
}:
{
  flake-file.inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  den.aspects.base = {
    includes = with den.aspects; [
      sops
      audio
      thunar
      system
      provision
      impermanence
      graalvm-oracle-21
      installer-tunables
    ];

    nixos = { pkgs, ... }: {
      # disko stays beside each host's device declaration.
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];

      nix.package = pkgs.lixPackageSets.stable.lix;

      # fleet disk layouts do not use zfs
      boot.zfs.forceImportRoot = false;

      # home-manager runs inside the system, sharing pkgs and overlays
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };

      # an empty declaration set still retires files from older generations.
      lexicon.furnish.enable = true;
    };
  };
}
