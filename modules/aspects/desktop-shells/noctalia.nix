{
  inputs,
  lexicon,
  rootPath,
  ...
}:
{
  flake-file.inputs.ai-usagebar = {
    url = "github:akitaonrails/ai-usagebar";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.noctalia = lexicon {
    homeManager =
      { pkgs, ... }:
      {
        home.packages = [
          inputs.ai-usagebar.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
      };

    furnish.directories = [
      {
        source = "${rootPath}/configs/noctalia";
        destination = ".config/noctalia";
      }
    ];
  };
}
