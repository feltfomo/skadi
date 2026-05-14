{
  self,
  inputs,
  ...
}:
{
  flake.nixosConfigurations.khion = inputs.nixpkgs.lib.nixosSystem {
    modules = [

      # external modules
      inputs.hjem.nixosModules.default
      inputs.lix-module.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
      }

      # internal modules to load for config
      self.nixosModules.noctalia-templates
      self.nixosModules.khionEnvironment
      self.nixosModules.khionNetworking
      self.nixosModules.khionHardware
      self.nixosModules.impermanence
      self.nixosModules.khionDisko
      self.nixosModules.spicetify
      self.nixosModules.packages
      self.nixosModules.programs
      self.nixosModules.hyprland
      self.nixosModules.security
      self.nixosModules.settings
      self.nixosModules.feltfom
      self.nixosModules.openssh
      self.nixosModules.nixvim
      self.nixosModules.nvidia
      self.nixosModules.fuzzel
      self.nixosModules.walker
      self.nixosModules.cursor
      self.nixosModules.thunar
      self.nixosModules.kitty
      self.nixosModules.steam
      self.nixosModules.home
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
