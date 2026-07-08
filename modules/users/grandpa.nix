{ den, ... }:
{
  den.aspects.grandpa = {
    # non-sudo, browser-only account. no primary-user (that is what adds wheel +
    # networkmanager) and no desktop/home aspects -- define-user just makes the
    # account and its home dir.
    includes = [
      den.batteries.define-user
    ];

    nixos =
      { pkgs, config, ... }:
      {
        # login password lives in sops, decrypted at activation. neededForUsers
        # so it is present when the account is created; such secrets take no
        # owner/mode. it rides secrets/lumi.yaml (encrypted to khion + lumi), not
        # khion's secrets.yaml -- so a lost laptop decrypts only this hash, never
        # khion's feltfomo/notion/hermes secrets.
        sops.secrets."grandpa-password" = {
          neededForUsers = true;
          sopsFile = ../../secrets/lumi.yaml;
        };

        users.users.grandpa = {
          isNormalUser = true;
          group = "grandpa";
          shell = pkgs.bash;
          hashedPasswordFile = config.sops.secrets."grandpa-password".path;
        };
        users.groups.grandpa = { };
      };

    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          firefox
          zed-editor
        ];
      };
  };
}
