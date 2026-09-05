{ inputs, ... }:
{
  flake-file.inputs.sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.sops.nixos =
    { host, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];
      sops = {
        defaultSopsFile = ../../secrets/${host.name}.yaml;
        validateSopsFiles = false;
        age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
        # age avoids the rsa to gpg import that failed in initrd
        gnupg.sshKeyPaths = [ ];
      };
    };
}
