{ inputs, ... }:
{
  den.aspects.sops.nixos =
    { ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];
      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        validateSopsFiles = false;
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        secrets = {
          "feltfomo-password".neededForUsers = true;
          "notion-token" = { owner = "feltfomo"; mode = "0400"; };
          "hermes-secrets" = { };
        };
      };
    };
}
