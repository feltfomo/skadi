{ ... }:
{
  flake.nixos.modules.terminalPackages =
    { ... }:
    {
      home-manager.users.feltfomo =
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            eza
          ];
        };
    };
}
