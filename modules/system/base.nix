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
      installer-tunables
      impermanence
      provision
      thunar
      system
      audio
      sops
    ];

    nixos = { pkgs, lib, ... }: {
      # disko stays beside each host's device declaration.
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];

      nix.package = pkgs.lixPackageSets.stable.lix;

      environment.systemPackages = with pkgs; [
        ffmpeg
        # Both wrappers provide cc/c++; prefer Clang for those shared names.
        (lib.hiPrio clang)
        unzip
        gcc
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
