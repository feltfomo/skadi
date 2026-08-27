# first-boot bootstrap: clone the wallpaper repo + notion-sync mapping repos into
# feltfomo's home if missing. runs as the user on the booted system, so paths
# resolve in the real namespace (no impermanence bind-mount guessing) and
# ownership is correct with no chown. self-healing: re-clones anything deleted.
_: {
  den.aspects.bootstrap-repos.homeManager =
    { pkgs, lib, ... }:
    let
      repos = {
        "Projects/notion-sync".url = "https://github.com/feltfomo/notion-sync";
        "Projects/multiloader-template".url = "https://github.com/feltfomo/multiloader-template";
        # this repo wraps its images in an inner Wallpapers/ dir; promote that
        # subdir so they land flat at ~/Wallpapers, not ~/Wallpapers/Wallpapers.
        "Wallpapers" = {
          url = "https://github.com/feltfomo/Wallpapers";
          subdir = "Wallpapers";
        };
      };
      bootstrap = pkgs.writeShellApplication {
        name = "bootstrap-repos";
        runtimeInputs = [
          pkgs.git
          pkgs.openssh
        ];
        text = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            rel: spec:
            let
              inherit (spec) url;
              subdir = spec.subdir or null;
            in
            if subdir == null then
              ''
                dest="$HOME/${rel}"
                if [ ! -e "$dest/.git" ]; then
                  mkdir -p "$(dirname "$dest")"
                  # user services can't reliably wait on the system network-online
                  # target (and feltfomo lingers), so retry instead of failing early.
                  for attempt in $(seq 1 30); do
                    echo "bootstrap-repos: cloning ${url} -> $dest (attempt $attempt)"
                    if git clone "${url}" "$dest"; then
                      break
                    fi
                    echo "bootstrap-repos: clone failed, retrying in 10s"
                    rm -rf "$dest"
                    sleep 10
                  done
                  [ -e "$dest/.git" ] || echo "bootstrap-repos: WARN gave up on ${url}"
                fi
              ''
            else
              ''
                dest="$HOME/${rel}"
                # ${url} nests its content under ${subdir}/; promote that subdir so
                # files land flat at $dest. the flattened tree keeps no top-level
                # .git, so non-emptiness is the "already cloned" sentinel.
                if [ -z "$(ls -A "$dest" 2>/dev/null || true)" ]; then
                  mkdir -p "$(dirname "$dest")"
                  for attempt in $(seq 1 30); do
                    echo "bootstrap-repos: cloning ${url} -> $dest (attempt $attempt)"
                    tmp="$(mktemp -d)"
                    if git clone --depth 1 "${url}" "$tmp/repo" && [ -d "$tmp/repo/${subdir}" ]; then
                      rm -rf "$dest"
                      mkdir -p "$(dirname "$dest")"
                      mv "$tmp/repo/${subdir}" "$dest"
                      rm -rf "$tmp"
                      break
                    fi
                    echo "bootstrap-repos: clone failed, retrying in 10s"
                    rm -rf "$tmp" "$dest"
                    sleep 10
                  done
                  [ -n "$(ls -A "$dest" 2>/dev/null || true)" ] || echo "bootstrap-repos: WARN gave up on ${url}"
                fi
              ''
          ) repos
        );
      };
    in
    {
      systemd.user.services.bootstrap-repos = {
        Unit = {
          Description = "Clone wallpaper + notion-sync mapping repos if missing";
          Wants = [ "network-online.target" ];
          After = [ "network-online.target" ];
        };
        Service = {
          # Home Manager starts newly enabled user units while reloadSystemd is
          # still inside home-manager-feltfomo.service. A retrying oneshot makes
          # that activation wait for every clone and hit its five-minute system
          # timeout when the network is unavailable. Type=exec acknowledges the
          # successful process launch immediately while the bootstrap continues
          # independently under the user manager.
          Type = "exec";
          ExecStart = "${bootstrap}/bin/bootstrap-repos";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
