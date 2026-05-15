{
  inputs,
  ...
}:
{
  flake.nixosConfigurations.lumi = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules =
      (with inputs.self.modules.nixos; [
        kitty
        gnome
        fuzzel
        thunar
        grandpa
        packages
        programs
        hyprland
        feltfomo
        spicetify
        lumi-modules
        impermanence
        noctalia-templates
      ])
      ++ [
        # external modules
        inputs.disko.nixosModules.disko
        inputs.hjem.nixosModules.default
        inputs.lix-module.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
        }
        # do not change
        { system.stateVersion = "25.11"; }
      ];
  };
}
