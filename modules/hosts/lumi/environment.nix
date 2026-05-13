{ ... }:
{
  flake.nixosModules.lumiEnvironment =
    { ... }:
    {
      environment = {
        variables = {
          EDITOR = "nvim";
        };
      };
    };
}
