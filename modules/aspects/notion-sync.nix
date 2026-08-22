{
  inputs,
  program,
  ...
}:
{
  den.aspects.notion-sync = program {
    nixos = { config, ... }: [
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

          # feltfomo owns the decrypted environment file read by the user service
          # the installer provisions it in the target host's encrypted secret file
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
              parent_page_id = "d6af6cb3d7ed4f7aa18ed110d5f0de28";
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
              parent_page_id = "7e0b191d6dfd420db7b01fb9cb4bcbb2";
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
              parent_page_id = "56e9411ee63a4483a4275599d0aedcf5";
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
              parent_page_id = "493c8c6ba7ae4006a532baa0d388657e";
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
              parent_page_id = "224835117f0b4ddaa73a1c628c4d3337";
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
              parent_page_id = "bc4d27a94ec94d07bf7d4d6b38a2d6a9";
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
              parent_page_id = "faac735dcc7b436dbbe010d765a60da3";
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
              parent_page_id = "17168541588743c1bbc5b250b1a9a3cf";
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
              name = "illogical-impulse-shell-nix";
              local_root = "/home/feltfomo/Projects/illogical-impulse-shell-nix";
              parent_page_id = "4975ed24237d4353a7a946a6b35a308f";
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
              parent_page_id = "efb8f20a480546fcb39e35979c963859";
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
              parent_page_id = "8b6da33078a74de7b505d1ed2ad879e0";
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
        hosts = [ "khion" ];
        services.notion-sync.keepWarm = {
          enable = true;
          url = "https://khion.tail4f0c8e.ts.net/notion-webhook";
          forcePublicPath = true;
        };
      }
    ];
  };
}
