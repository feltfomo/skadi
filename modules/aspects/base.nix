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
    lix = {
      # 2026-08-01's da4a2da evaluator corrupted multi-output string contexts.
      url = "https://git.lix.systems/lix-project/lix/archive/64c99ac9af9c83b66643f46e9c8e50ab9f5e6e58.tar.gz";
      flake = false;
    };
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
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

    nixos = {
      # disko stays beside each host's device declaration.
      imports = [
        inputs.home-manager.nixosModules.home-manager
        inputs.lix-module.nixosModules.default
      ];

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
