{ inputs, ... }:
{
  # the repository is private, so nix fetches it over ssh
  flake-file.inputs.enishi = {
    url = "git+ssh://git@github.com/feltfomo/enishi";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.enishi.nixos = {
    imports = [ inputs.enishi.nixosModules.default ];

    services.enishi = {
      enable = true;
      settings = {
        # the coordinator order: the first machine leads, as go's primary did
        machines = [
          {
            name = "khion";
            ssh = "khion";
          }
          {
            name = "lumi";
            ssh = "lumi";
          }
        ];
        queue = {
          light_capacity = 2;
          aging_limit_ms = 1800000;
          default_estimate_ms = 600000;
        };
        projects.odyssey = {
          priority = 100;
          heavy = [ "^devenv test" ];
          pins = [
            {
              pattern = "^devenv test";
              machine = "khion";
            }
          ];
        };
        # this repository's gates recorded `junban` before its folder was renamed
        projects.enishi = {
          formerly = [ "junban" ];
        };
      };
    };
  };
}
