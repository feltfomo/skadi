{ inputs, ... }:
{
  den.aspects.noctalia-greeter = {
    # synced appearance plus the remembered session and color scheme.
    persistence.directories = [ "/var/lib/noctalia-greeter" ];

    nixos = {
      imports = [ inputs.noctalia-greeter.nixosModules.default ];
      programs.noctalia-greeter.enable = true;
      security.polkit.enable = true;
    };
  };
}
