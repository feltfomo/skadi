{ inputs, ... }:
{
  den.aspects.notion-sync.nixos =
    { config, ... }:
    {
      imports = [ inputs.notion-sync.nixosModules.notion-sync ];

      # the token secret + how the installer provisions it, owned here next to
      # the service that consumes it (moved out of the monolithic sops.nix).
      # optional: a blank paste falls back to the REPLACE_ME placeholder.
      sops.secrets."notion-token" = {
        owner = "feltfomo";
        mode = "0400";
      };
      skadi.provision.secrets.notion-token = {
        method = "paste";
        prompt = "NOTION_TOKEN (ntn_…) — blank for placeholder";
        format = "NOTION_TOKEN=%s";
        optional = true;
        placeholder = "NOTION_TOKEN=REPLACE_ME";
      };

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
            parent_page_id = "39320fa1c54580fbb131d699f23675a5";
            ignore = [
              ".git"
              "target"
              "node_modules"
              "*.lock"
              "result"
              "result-*"
              "dist"
              ".notion-sync"
              "config.toml"
              # VM / build binaries -- never sync large images (they OOM-balloon the daemon)
              "*.qcow2"
              "*.iso"
              "*.img"
              "*.raw"
              "*.fd"
            ];
          }
          {
            name = "skadi";
            local_root = "/etc/skadi";
            parent_page_id = "39320fa1c545803cbf5fd2e299bbe199";
            ignore = [
              ".git"
              "result"
              "result-*"
              "node_modules"
              "*.lock"
              ".direnv"
              "assets"
              "secrets"
              ".notion-sync"
              # VM / build binaries -- never sync large images. the qcow2 disk +
              # `result` ISO grow on every build/install; syncing them ballooned the
              # daemon to ~19G RAM and triggered a kernel OOM crash-loop (restart x22).
              "*.qcow2"
              "*.iso"
              "*.img"
              "*.raw"
              "*.fd"
              "*.ova"
              "*.vdi"
            ];
          }
          {
            name = "multiloader-template";
            local_root = "/home/feltfomo/Projects/multiloader-template";
            parent_page_id = "39320fa1c54580d48175d24cbe21212c";
            ignore = [
              ".git"
              "build"
              ".gradle"
              ".kotlin"
              ".pkl-generated"
              "generated"
              ".idea"
              "result"
              "result-*"
              "node_modules"
              "run"
              "*.salive"
              ".notion-sync"
              # VM / build binaries -- never sync large images (OOM guard)
              "*.qcow2"
              "*.iso"
              "*.img"
              "*.raw"
              "*.fd"
            ];
          }
        ];
      };
    };
}
