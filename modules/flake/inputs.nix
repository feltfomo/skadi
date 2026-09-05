{ inputs, ... }:
{
  imports = [ inputs.flake-file.flakeModules.default ];

  flake-file = {
    description = "skadi";
    inputs = {
      flake-file.url = "github:denful/flake-file/v0.3.0";
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      import-tree.url = "github:vic/import-tree";
      flake-parts.url = "github:hercules-ci/flake-parts";
      # lexicon owns the shared ownership and program framework.
      lexicon = {
        url = "github:feltfomo/lexicon";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      # host and installer disk layouts share the same disko module.
      disko = {
        url = "github:nix-community/disko";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    };
  };
}
