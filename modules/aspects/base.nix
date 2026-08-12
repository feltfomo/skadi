{
  inputs,
  den,
  ...
}:
{
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

      # home-manager runs inside the system, sharing pkgs and overlays
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };

      # an empty declaration set still retires files from older generations.
      lexicon.furnish.enable = true;
    };
  };
}
