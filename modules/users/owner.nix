{ den, ... }:
{
  den.aspects.owner = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
    ];

    # define-user makes a normal user and sets the home dir; primary-user adds
    # wheel + networkmanager. no home aspects on purpose: the generic install is
    # a lean base for a stranger's machine, so `owner` is the machine's clean
    # primary admin account -- no desktop / home-manager closure. CLI essentials
    # (shell, git, editor) come from base at the system level, not per-user.
    nixos =
      { config, ... }:
      {
        # login password + how the installer provisions it, declared right next
        # to the user that needs it (same trio as feltfomo.nix). skadi-install
        # fills owner-password via mkpasswd; the vm-test harness feeds the
        # deterministic test hash through SKADI_SECRET_OWNER_PASSWORD.
        sops.secrets."owner-password".neededForUsers = true;
        skadi.provision.secrets.owner-password = {
          method = "mkpasswd";
          prompt = "login password for owner";
        };

        users.users.owner.hashedPasswordFile = config.sops.secrets."owner-password".path;
      };
  };
}
