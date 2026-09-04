{ den, ... }:
{
  den.aspects.owner = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
    ];

    # owner is the lean primary admin account for generic installations.
    # base provides shell, git, and editor packages without a home-manager closure.
    nixos =
      { config, ... }:
      {
        # skadi-install provisions owner-password through mkpasswd.
        # vm-test supplies the deterministic hash through SKADI_SECRET_OWNER_PASSWORD.
        sops.secrets."owner-password".neededForUsers = true;
        skadi.provision.secrets.owner-password = {
          method = "mkpasswd";
          prompt = "login password for owner";
        };

        users.users.owner.hashedPasswordFile = config.sops.secrets."owner-password".path;
      };
  };
}
