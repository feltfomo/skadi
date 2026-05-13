{
  self,
  inputs,
  ...
}:
{
  flake.nixosConfigurations.lumi = inputs.nixpkgs.lib.nixosSystem {
    modules = [

      # external modules
      inputs.lix-module.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
      }

      # internal modules to load for config
      self.nixosModules.lumiEnvironment
      self.nixosModules.lumiNetworking
      self.nixosModules.lumiHardware
      self.nixosModules.impermanence
      self.nixosModules.lumiDisko
      self.nixosModules.spicetify
      self.nixosModules.packages
      self.nixosModules.programs
      self.nixosModules.hyprland
      self.nixosModules.security
      self.nixosModules.settings
      self.nixosModules.openssh
      self.nixosModules.fuzzel
      self.nixosModules.walker
      self.nixosModules.cursor
      self.nixosModules.thunar
      self.nixosModules.gnome
      self.nixosModules.steam
      self.nixosModules.home
      self.nixosModules.user
      self.nixosModules.fish
      self.nixosModules.boot
      self.nixosModules.nyx
      self.nixosModules.git
      self.nixosModules.gtk
      self.nixosModules.qt
      self.nixosModules.gc

      # do not change
      { system.stateVersion = "25.11"; }
    ];
  };
}
