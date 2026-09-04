{ config, lib, ... }:
let
  fixture = ../secrets.yaml;
  expectedSecrets = [ "feltfomo-password" ];
  actualSecrets = lib.sort builtins.lessThan (builtins.attrNames config.sops.secrets);
in
{
  # the harness generates this disposable vm-only sops fixture.
  # its throwaway recipient must never enter real rules or host configuration.
  sops.secrets."feltfomo-password".sopsFile = lib.mkForce fixture;

  # keep the harness transport key on the installed vm for first-boot checks.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkForce "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOgAOLIbgZ8Smas/KvnWNOaMzCDrZ5RFDUvQ+08MZ8Uh skadi-vm-test"
  ];

  assertions = [
    {
      assertion = actualSecrets == expectedSecrets;
      message = "vm test identity requires exactly feltfomo-password";
    }
    {
      assertion = toString config.sops.secrets."feltfomo-password".sopsFile == toString fixture;
      message = "vm secrets must use only the generated vm test fixture";
    }
  ];
}
