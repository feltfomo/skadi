{
  description = "flake for skadi`";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    impermanence.url = "github:nix-community/impermanence";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      impermanence,
      disko,
      ...
    }@inputs:
    {
      nixosConfigurations.lumi = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          impermanence.nixosModules.impermanence
          disko.nixosModules.disko
          ./configuration.nix
        ];
      };
    };
}
