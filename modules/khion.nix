{
  inputs,
  ...
}:
{
  flake.nixosConfigurations.khion = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules =
      (with inputs.self.modules.nixos; [
        kitty
        steam
        qt-hm
        fuzzel
        thunar
        walker
        firefox
        noctalia
        packages
        programs
        hyprland
        feltfomo
        spicetify
        impermanence
        khion-modules
        wayland-packages
        graalvm-oracle-21
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
