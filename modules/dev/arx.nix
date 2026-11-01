{ inputs, ... }:
{
  # the repository is private, so nix fetches it over ssh
  flake-file.inputs.arx = {
    url = "git+ssh://git@github.com/feltfomo/arx";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.arx.homeManager = { pkgs, ... }: {
    home.packages = [ inputs.arx.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  };
}
