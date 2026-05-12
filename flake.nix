{
  description = "flake for skadi";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    hyprland.url = "github:hyprwm/Hyprland";
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
  };

  outputs =
    {
      home-manager,
      impermanence,
      nixpkgs,
      disko,
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
          disko.nixosModules.disko
          ./hosts/lumi/configuration.nix
        ];
      };
      nixosConfigurations.khion = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          impermanence.nixosModules.impermanence
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.feltfomo = import ./home.nix;
          }
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
