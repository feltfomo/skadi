{
  inputs,
  program,
  ...
}: {
  den.aspects.notion-sync = program {
    nixos = {config, ...}: [
      {
        imports = [inputs.notion-sync.nixosModules.notion-sync];

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

        environment.systemPackages = [config.services.notion-sync.package];

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
              parent_page_id = "9addd8564d16438d9f02d9feae1c7631";
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
              parent_page_id = "4893908605e4489196431a8d3f082db2";
              ignore = [
                ".git"
                "result"
                "result-*"
                "node_modules"
                "target"
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
              parent_page_id = "aa2de8075afd420fad741b422355b133";
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
            {
              # axiom's own repo now. skadi consumes it as a flake input and
              # keeps no copy of its own.
              name = "axiom-nix";
              local_root = "/home/feltfomo/Projects/axiom-nix";
              parent_page_id = "a6ba082e236d46cdb3ea6104b9407750";
              ignore = [
                ".git"
                "result"
                "result-*"
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
            {
              # split out alongside axiom, and takes axiom as a flake input
              # rather than a relative import.
              name = "krisis";
              local_root = "/home/feltfomo/Projects/krisis";
              parent_page_id = "890586d8f09f4c8e895d692288ececd9";
              ignore = [
                ".git"
                "result"
                "result-*"
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
            {
              # the rust coordinator, split out of furnish. owns its own crate and
              # its build definition, and hands furnish a function of pkgs.
              name = "furnish-coordinator";
              local_root = "/home/feltfomo/Projects/furnish-coordinator";
              parent_page_id = "cc848aa34d6a489b815df1905fc901c2";
              ignore = [
                ".git"
                "result"
                "result-*"
                "target"
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
            {
              # furnish, ownerships, program, program.nix, and den.nix in one
              # repo. takes axiom, krisis, and the coordinator as flake inputs.
              name = "lexicon";
              local_root = "/home/feltfomo/Projects/lexicon";
              parent_page_id = "1e5643c5a6244bbdba6b30056accc54b";
              ignore = [
                ".git"
                "result"
                "result-*"
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
            {
              name = "den";
              local_root = "/home/feltfomo/Reference-Projects/den";
              parent_page_id = "dc76796d5d4648d9a083557dc4e29994";
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
            {
              name = "dots-hyprland";
              local_root = "/home/feltfomo/Reference-Projects/dots-hyprland";
              parent_page_id = "912fa25a13d94c4c8003beb02b9df96f";
              ignore = [
                ".git"
                "result"
                "result-*"
                "node_modules"
                ".direnv"
                ".venv"
                "__pycache__"
                ".notion-sync"
                # Reference tree: keep source and small assets, but never mirror
                # build products or large binary images into Notion.
                "build"
                "dist"
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
              name = "end4-pC";
              local_root = "/home/feltfomo/Reference-Projects/end4-pC";
              parent_page_id = "bb05209502ff4c3f870319799ce8ad14";
              ignore = [
                ".git"
                "result"
                "result-*"
                "node_modules"
                ".direnv"
                ".venv"
                "__pycache__"
                ".notion-sync"
                "material_symbols_rounded.json"
                # Reference tree: keep source and small assets, but never mirror
                # build products or large binary images into Notion.
                "build"
                "dist"
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
              name = "illogical-impulse-shell-nix";
              local_root = "/home/feltfomo/Projects/illogical-impulse-shell-nix";
              parent_page_id = "982d5121eaf04c0781e82be1c82b0c58";
              ignore = [
                ".git"
                "result"
                "result-*"
                ".direnv"
                ".venv"
                "__pycache__"
                ".pytest_cache"
                ".ruff_cache"
                ".mypy_cache"
                "build"
                "dist"
                ".notion-sync"
                # Keep source assets and flake.lock, but never mirror large images.
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
              name = "nix-effects";
              local_root = "/home/feltfomo/Reference-Projects/nix-effects";
              parent_page_id = "5365cb6797df46409f4929f42d705e55";
              ignore = [
                ".git"
                "result"
                "result-*"
                "*.lock"
                ".direnv"
                ".notion-sync"
                "*.qcow2"
                "*.iso"
                "*.img"
                "*.raw"
                "*.fd"
              ];
            }
            {
              name = "workflow-workbench";
              local_root = "/home/feltfomo/Projects/workflow-workbench";
              parent_page_id = "6f71915d02bb406e994685e47d099094";
              ignore = [
                ".git"
                "result"
                "result-*"
                "__pycache__"
                ".pytest_cache"
                ".ruff_cache"
                ".mypy_cache"
                ".direnv"
                "dist"
                "*.pyz"
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
        hosts = ["khion"];
        services.notion-sync.keepWarm = {
          enable = true;
          url = "https://khion.tail4f0c8e.ts.net/notion-webhook";
          forcePublicPath = true;
        };
      }
    ];
  };
}
