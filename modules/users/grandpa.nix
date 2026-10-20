{ den, ... }:
{
  den.aspects.grandpa = {
    # omit primary-user to keep this account out of wheel and networkmanager.
    includes = [
      den.batteries.define-user
    ];

    nixos =
      { pkgs, config, ... }:
      {
        sops.secrets."grandpa-password".neededForUsers = true;
        skadi.provision.secrets.grandpa-password = {
          method = "mkpasswd";
          prompt = "login password for grandpa";
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
          zed-editor
          firefox
        ];
      };
  };
}
