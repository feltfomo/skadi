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
