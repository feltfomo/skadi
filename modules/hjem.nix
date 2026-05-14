{ ... }:
{
  flake.nixosModules.hjem =
    { ... }:
    {
      # set feltfomo as a hjem user and sets dir
      hjem.users = {
        feltfomo = {
          enabled = true;
          user = "feltfomo";
          directory = "/home/feltfomo";
        };
      };
    };
}
