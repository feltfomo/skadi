{
  den.aspects.networking = {
    persistence.directories = [ "/etc/NetworkManager/system-connections" ];

    nixos =
      { host, ... }:
      {
        # networkmanager everywhere; hostname derived from the den host name
        networking = {
          networkmanager.enable = true;
          hostName = host.name;
        };
      };
  };
}
