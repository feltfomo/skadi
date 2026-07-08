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
        # owner/mode. the encrypted value is added to secrets/secrets.yaml out
        # of band, and lumi must be a recipient in .sops.yaml to decrypt it.
        sops.secrets."grandpa-password".neededForUsers = true;

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
