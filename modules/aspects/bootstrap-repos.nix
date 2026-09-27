# the user service reclones missing repos when it starts.
_: {
  den.aspects.bootstrap-repos.homeManager =
    { pkgs, lib, ... }:
    let
      repos = {
        "Projects/multiloader-template".url = "https://github.com/feltfomo/multiloader-template";
        # the repo nests images under Wallpapers/; the destination keeps them flat.
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
                  # target, so retry instead of failing early.
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
                # moving ${subdir} drops .git, so non-emptiness marks a completed clone.
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
          Description = "Clone wallpaper and project repos if missing";
          Wants = [ "network-online.target" ];
          After = [ "network-online.target" ];
        };
        Service = {
          Type = "exec";
          ExecStart = "${bootstrap}/bin/bootstrap-repos";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
