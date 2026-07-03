# First-boot bootstrap: clone the wallpaper repo + notion-sync mapping repos
# into feltfomo's home if missing. Runs as the user on the booted system, so
# paths resolve in the real namespace (no impermanence bind-mount guessing) and
# ownership is correct with no chown. Self-healing: re-clones anything deleted.
_: {
  den.aspects.bootstrap-repos.homeManager =
    { pkgs, lib, ... }:
    let
      repos = {
        "Projects/notion-sync" = "https://github.com/feltfomo/notion-sync";
        "Projects/multiloader-template" = "https://github.com/feltfomo/multiloader-template";
        "Wallpapers" = "https://github.com/feltfomo/Wallpapers";
      };
      bootstrap = pkgs.writeShellApplication {
        name = "bootstrap-repos";
        runtimeInputs = [
          pkgs.git
          pkgs.openssh
        ];
        text = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (rel: url: ''
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
          '') repos
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
          Type = "oneshot";
          ExecStart = "${bootstrap}/bin/bootstrap-repos";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
