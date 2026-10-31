{ inputs, ... }:
{
  # the repository is private, so nix fetches it over ssh
  flake-file.inputs.junban = {
    url = "git+ssh://git@github.com/feltfomo/Junban";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.junban.nixos = {
    imports = [ inputs.junban.nixosModules.default ];

    services.junban = {
      enable = true;
      settings = {
        primary = "khion";
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
        light_capacity = 2;
        aging_limit = "30m";
        default_estimate = "10m";
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
      };
    };
  };
}
