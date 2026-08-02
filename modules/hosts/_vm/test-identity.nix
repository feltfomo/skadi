{ config, lib, ... }:
let
  fixture = ./secrets.yaml;
  expectedSecrets = [
    "feltfomo-password"
    "notion-token"
  ];
  actualSecrets = lib.sort builtins.lessThan (builtins.attrNames config.sops.secrets);
in
{
  # Disposable-VM-only SOPS fixture, generated afresh by the golden harness.
  # Its throwaway recipient must never enter real creation rules or host config.
  sops.secrets = {
    "feltfomo-password".sopsFile = lib.mkForce fixture;
    "notion-token".sopsFile = lib.mkForce fixture;
  };

  # The installer ISO already trusts this public half for the harness's
  # transport key. Keep the same test-only key on the installed VM so the
  # first-boot and overlay proofs can reconnect after the ISO is removed.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkForce "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElUx+G8NdV6W0NVEh3wpOg33mBnHY0oG9b31eds/LSs skadi-vm-test"
  ];

  assertions = [
    {
      assertion = actualSecrets == expectedSecrets;
      message = "vm test identity requires exactly feltfomo-password and notion-token";
    }
    {
      assertion =
        toString config.sops.secrets."feltfomo-password".sopsFile == toString fixture
        && toString config.sops.secrets."notion-token".sopsFile == toString fixture;
      message = "vm secrets must use only the generated _vm test fixture";
    }
  ];
}
