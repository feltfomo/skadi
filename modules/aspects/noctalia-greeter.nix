{ inputs, ... }:
{
  den.aspects.noctalia-greeter.nixos = {
    imports = [ inputs.noctalia-greeter.nixosModules.default ];
    programs.noctalia-greeter.enable = true;
    security.polkit.enable = true;
  };
}
