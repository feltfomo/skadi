{ inputs, ... }:
{
  den.aspects.notion-sync.nixos =
    { config, ... }:
    {
      imports = [ inputs.notion-sync.nixosModules.notion-sync ];

      environment.systemPackages = [ config.services.notion-sync.package ];

      services.notion-sync = {
        enable = true;

        # the daemon scaffolds this on first run; set local_root + parent_page_id
        # there. the token is never read from this file.
        configFile = "/home/feltfomo/.config/notion-sync/config.toml";

        # NOTION_TOKEN=ntn_... decrypted by sops-nix to /run/secrets/notion-token,
        # owned by feltfomo so the user service can read it. provision the value in
        # secrets/secrets.yaml before relying on it (see README).
        environmentFile = config.sops.secrets."notion-token".path;

        logLevel = "info";
      };
    };
}
