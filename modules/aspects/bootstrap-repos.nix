# the user service reclones missing repos when it starts.
_: {
  den.aspects.bootstrap-repos.homeManager =
    { pkgs, lib, ... }:
    let
      repos = {
        "Projects/multiloader-template".url = "https://github.com/feltfomo/multiloader-template";
        # the repo nests images under Pictures/; the destination keeps them flat.
        "Wallpapers" = {
          url = "https://github.com/feltfomo/Wallpapers";
          subdir = "Pictures";
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
                    tmp="$(mktemp -d "$(dirname "$dest")/.bootstrap-repos.XXXXXX")"
                    if git clone "${url}" "$tmp/repo" && mv -T "$tmp/repo" "$dest"; then
                      rm -rf "$tmp"
                      break
                    fi
                    echo "bootstrap-repos: clone failed, retrying in 10s"
                    rm -rf "$tmp"
                    [ ! -e "$dest" ] || break
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
                    tmp="$(mktemp -d "$(dirname "$dest")/.bootstrap-repos.XXXXXX")"
                    if git clone --depth 1 "${url}" "$tmp/repo" \
                      && [ -d "$tmp/repo/${subdir}" ] \
                      && mv -T "$tmp/repo/${subdir}" "$dest"; then
                      rm -rf "$tmp"
                      break
                    fi
                    echo "bootstrap-repos: clone failed, retrying in 10s"
                    rm -rf "$tmp"
                    [ -z "$(ls -A "$dest" 2>/dev/null || true)" ] || break
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
