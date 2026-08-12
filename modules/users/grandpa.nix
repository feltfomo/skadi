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
