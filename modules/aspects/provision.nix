{
  den.aspects.provision.nixos =
    { lib, ... }:
    {
      # each secret-bearing aspect declares how skadi-install fills its secret.
      # the installer loops over config.skadi.provision.secrets.
      options.skadi.provision.secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              method = lib.mkOption {
                type = lib.types.enum [
                  "mkpasswd"
                  "paste"
                  "placeholder"
                ];
              };
              prompt = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              # printf template applied to a pasted value such as "API_TOKEN=%s"
              format = lib.mkOption {
                type = lib.types.str;
                default = "%s";
              };
              optional = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              placeholder = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
              # literal value for method = "placeholder"
              value = lib.mkOption {
                type = lib.types.str;
                default = "";
              };
            };
          }
        );
      };
    };
}
