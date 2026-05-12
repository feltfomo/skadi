{
  description = "flake for skadi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hyprland.url = "github:hyprwm/Hyprland";
    impermanence.url = "github:nix-community/impermanence";
    spicetify-nix.url = "github:Gerg-L/spicetify-nix";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lix = {
      url = "https://git.lix.systems/lix-project/lix/archive/main.tar.gz";
      flake = false;
    };

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
    };
  };

  outputs =
    {
      home-manager,
      impermanence,
      lix-module,
      nixpkgs,
      disko,
      lix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.lumi = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          impermanence.nixosModules.impermanence
          lix-module.nixosModules.default
          disko.nixosModules.disko
          ./hosts/lumi/configuration.nix
        ];
      };
      nixosConfigurations.khion = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.feltfomo = import ./home.nix;
          }
          lix-module.nixosModules.default
          disko.nixosModules.disko
          ./hosts/khion/configuration.nix
        ];
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          lua
          stylua
          lua-language-server
        ];
      };
    };
}
