{ inputs, den, ... }:
{
  den.aspects.hermes.nixos = {
    imports = [ inputs.hermes-agent.nixosModules.default ];

    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;

      # telegram, discord and slack bridges
      extraDependencyGroups = [ "messaging" ];

      # writable ubuntu container so the agent can install its own tools
      container = {
        enable = true;
        backend = "docker";
        hostUsers = [ "feltfomo" ];
      };

      settings = {
        model = {
          provider = "nvidia";
          default = "nvidia/nemotron-3-super-120b-a12b";
        };
        toolsets = [ "all" ];
      };

      # nvidia build key and bot tokens, kept out of the store
      environmentFiles = [ "/var/lib/hermes/secrets.env" ];
    };
  };
}
