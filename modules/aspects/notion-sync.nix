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
              parent_page_id = "3b6d2f09c86980da9cc6e181db780f17";
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
              parent_page_id = "3b6d2f09c86980d1b357f8f6befc3f59";
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
              parent_page_id = "3b6d2f09c869805aab98d52be64ac0d0";
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
              # extracted out of skadi's modules/_lib, which still carries its own
              # copy until the flake input lands.
              name = "axiom-nix";
              local_root = "/home/feltfomo/Projects/axiom-nix";
              parent_page_id = "3b6d2f09c869803ba5ddeaf8810d704b";
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
              # extracted out of skadi's modules/_lib alongside axiom, and takes
              # axiom as a flake input rather than a relative import.
              name = "krisis";
              local_root = "/home/feltfomo/Projects/krisis";
              parent_page_id = "3b6d2f09c8698066bd81e2403554adcb";
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
              parent_page_id = "3b6d2f09c869800abbc9ffe500a2c0d9";
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
              parent_page_id = "3b6d2f09c8698097bc75c00c8646e7a9";
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
              parent_page_id = "3b6d2f09c86980e48033d30c15a170c6";
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
              parent_page_id = "3b6d2f09c8698004bfced47bb59ceb62";
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
              parent_page_id = "3b6d2f09c86980f5ba28d7d4c2dffdb2";
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
              parent_page_id = "3b6d2f09c869805a959bc2763ace6f94";
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
              name = "workflow-workbench";
              local_root = "/home/feltfomo/Projects/workflow-workbench";
              parent_page_id = "3b6d2f09c86980b3a9ead532116c0718";
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
