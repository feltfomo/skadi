{
  den.aspects.nix-development.homeManager = { pkgs, ... }: {
    home.packages = with pkgs; [
      alejandra
      deadnix
      nixfmt
      statix
      nixd
      nil
    ];
  };
}
