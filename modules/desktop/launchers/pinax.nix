{ inputs, lexicon, ... }:
{
  # the repository is private, so nix fetches it over ssh
  flake-file.inputs.pinax = {
    url = "git+ssh://git@github.com/feltfomo/pinax";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.pinax = lexicon {
    package = pkgs: inputs.pinax.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
