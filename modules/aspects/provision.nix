{ ... }:
{
  den.aspects.provision.nixos =
    { lib, ... }:
    {
      # provisioning policy as data: each secret-bearing aspect declares, right
      # next to its own sops secret, how skadi-install should fill it. the
      # installer evals config.skadi.provision.secrets and loops over it, so
      # adding a user or a secret never means editing the script.
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
              # printf template applied to a pasted value, e.g. "NOTION_TOKEN=%s"
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