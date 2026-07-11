{ inputs, resolveSystem, ... }:
{
  den.aspects.notion-sync =
    { host, ... }:
    {
      nixos =
        { config, ... }:
        resolveSystem [
          {
            imports = [ inputs.notion-sync.nixosModules.notion-sync ];

            # the token secret + how the installer provisions it, owned next to the
            # service that consumes it. optional: a blank paste falls back to the
            # REPLACE_ME placeholder.
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

              # funnel already terminates TLS and forwards to 127.0.0.1:8080, so the
              # listener defaults match -- just enable it. no signing secret here: the
              # daemon persists notion's first-connect verification_token itself.
              settings.webhook = {
                enabled = true;
                port = 8080;
              };

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
                    # result ISO grow on every build/install; syncing them ballooned the
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
                # reference clone of den -- read-only source exploration (see "Exploring den")
                {
                  name = "den";
                  local_root = "/home/feltfomo/Reference-Projects/den";
                  parent_page_id = "39820fa1c545807390dbe045848a4d47";
                  ignore = [
                    ".git"
                    "result"
                    "result-*"
                    "node_modules"
                    "*.lock"
                    ".direnv"
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
          }
          {
            # only khion keeps warm -- it owns the funnel. an idle funnel ingress goes
            # cold and 502s the next request, dropping notion's one-shot webhook
            # deliveries. forcePublicPath is required: a ping from khion itself never
            # crosses the ingress (direct tailnet path). the unit above stays untagged
            # (global), so every other host drops this unit and keeps keepWarm at its
            # module default -- only this one field is host-narrowed.
            hosts = [ "khion" ];
            services.notion-sync.keepWarm = {
              enable = true;
              url = "https://khion.tail4f0c8e.ts.net/notion-webhook";
              forcePublicPath = true;
            };
          }
        ] { inherit host; };
    };
}
