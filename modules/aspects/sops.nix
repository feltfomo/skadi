{ inputs, ... }:
{
  den.aspects.sops.nixos =
    { ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];
      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        validateSopsFiles = false;
        age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
        # decrypt via age only; stops the RSA->GPG import that fails in initrd
        gnupg.sshKeyPaths = [ ];
        secrets = {
          "feltfomo-password".neededForUsers = true;
          "notion-token" = {
            owner = "feltfomo";
            mode = "0400";
          };
          "hermes-secrets" = { };
        };
      };
    };
}
