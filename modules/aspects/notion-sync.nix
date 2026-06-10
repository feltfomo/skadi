{ inputs, ... }:
{
  den.aspects.notion-sync.nixos =
    { config, ... }:
    {
      imports = [ inputs.notion-sync.nixosModules.notion-sync ];

      environment.systemPackages = [ config.services.notion-sync.package ];

      services.notion-sync = {
        enable = true;

        # NOTION_TOKEN=ntn_... decrypted by sops-nix to /run/secrets/notion-token,
        # owned by feltfomo so the user service can read it. provision the value in
        # secrets/secrets.yaml before relying on it (see README).
        environmentFile = config.sops.secrets."notion-token".path;

        logLevel = "info";

        # push path: Notion -> Funnel (tailscale) -> this loopback listener, so
        # remote edits land in seconds instead of waiting on the 45s poll. the
        # poller stays on as the fallback for missed deliveries. funnel terminates
        # TLS and forwards to 127.0.0.1:8080, so the listener defaults already
        # match -- just flip it on. the signing secret isn't set here: Notion posts
        # its verification_token on first connect and the daemon persists it under
        # ~/.local/state/notion-sync/webhook_secret (user service, so that's writable).
        settings.webhook = {
          enabled = true;
          port = 8080;
        };

        # declarative config -- the module renders this to a store-side config.toml
        # and passes it via --config. NO secrets land here (the token only ever
        # comes from environmentFile above), so a world-readable store path is fine.
        # mapping names derive from the last path component; state.db rows are
        # namespaced under exactly those names, so keep the names + roots stable.
        settings.mapping = [
          {
            name = "notion-sync";
            local_root = "/home/feltfomo/Projects/notion-sync";
            parent_page_id = "378f23c5af9580a59a6dc218fa24b366";
            ignore = [ ".git" "target" "node_modules" "*.lock" "result" "dist" ".notion-sync" "config.toml" ];
          }
          {
            name = "skadi";
            local_root = "/etc/skadi";
            parent_page_id = "37af23c5af95803ba445d8dc595ac03b";
            ignore = [ ".git" "result" "node_modules" "*.lock" ".direnv" "assets" ".notion-sync" ];
          }
          {
            name = "multiloader-template";
            local_root = "/home/feltfomo/Projects/multiloader-template";
            parent_page_id = "37af23c5af9580d7a823f972170f2a5b";
            ignore = [ ".git" "build" ".gradle" ".kotlin" ".pkl-generated" ".idea" "result" "result-*" "node_modules" "run" "*.salive" ".notion-sync" ];
          }
        ];
      };
    };
}
