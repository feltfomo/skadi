{ inputs, ... }:
{
  # the repository is private, so nix fetches it over ssh. pinned to the last herdr build.
  flake-file.inputs.arx = {
    url = "git+ssh://git@github.com/feltfomo/arx?ref=effort/client&rev=2af4a0391756f0d4d1ecc6fe5ceb4d842edf1a1c";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.arx.homeManager = { pkgs, ... }: {
    home.packages = [ inputs.arx.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  };
}
