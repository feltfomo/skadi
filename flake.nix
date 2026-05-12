{
  description = "flake for skadi";

  # caches
  nixConfig = {
    extra-substituters = [
      "https://hyprland.cachix.org"
      "https://walker.cachix.org"
      "https://walker-git.cachix.org"
      "https://noctalia.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };

  # flake inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hyprland.url = "github:hyprwm/Hyprland";
    elephant.url = "github:abenz1267/elephant";
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
    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };
  };

  # flake outputs
  outputs =
    {
      home-manager,
      impermanence,
      lix-module,
      nixpkgs,
      disko,
      ...
    }@inputs:
    let
      spicePkgs = inputs.spicetify-nix.legacyPackages.${system};
      mkSystem = nixpkgs.lib.nixosSystem;
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {

      nixosConfigurations = {

        # lumi machine (laptop)
        lumi = mkSystem {
          specialArgs = { inherit inputs system spicePkgs; };
          modules = [
            home-manager.nixosModules.home-manager
            impermanence.nixosModules.impermanence
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs system spicePkgs; };
              home-manager.users.feltfomo = import ./home.nix;
            }
            lix-module.nixosModules.default
            disko.nixosModules.disko
            ./hosts/lumi/configuration.nix
          ];
        };

        # khion machine (desktop)
        khion = mkSystem {
          specialArgs = { inherit inputs system spicePkgs; };
          modules = [
            home-manager.nixosModules.home-manager
            impermanence.nixosModules.impermanence
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs system spicePkgs; };
              home-manager.users.feltfomo = import ./home.nix;
            }
            lix-module.nixosModules.default
            disko.nixosModules.disko
            ./hosts/khion/configuration.nix
          ];
        };
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
