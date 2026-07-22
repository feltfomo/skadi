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
  # Disposable-VM-only SOPS fixture. Its committed test identity must never be
  # added to real creation rules or used by a real host.
  sops.secrets = {
    "feltfomo-password".sopsFile = lib.mkForce fixture;
    "notion-token".sopsFile = lib.mkForce fixture;
  };

  assertions = [
    {
      assertion = actualSecrets == expectedSecrets;
      message = "vm test identity requires exactly feltfomo-password and notion-token";
    }
    {
      assertion =
        toString config.sops.secrets."feltfomo-password".sopsFile == toString fixture
        && toString config.sops.secrets."notion-token".sopsFile == toString fixture;
      message = "vm secrets must use only the committed _vm test fixture";
    }
  ];
}
