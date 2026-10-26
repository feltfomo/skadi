# the user service reclones missing repos when it starts.
_: {
  den.aspects.bootstrap-repos.homeManager =
    { pkgs, lib, ... }:
    let
      repos = {
        "Projects/lexicon" = "https://github.com/feltfomo/lexicon";
        "Projects/odyssey" = "https://github.com/feltfomo/odyssey";
        "Projects/furnish-coordinator" = "https://github.com/feltfomo/furnish-coordinator";
        "Projects/axiom-nix" = "https://github.com/feltfomo/axiom-nix";
        "Projects/illogical-impulse-shell-nix" = "https://github.com/feltfomo/illogical-impulse-shell-nix";
        "Projects/skills" = "https://github.com/feltfomo/skills";
        "Wallpapers" = "https://github.com/feltfomo/Wallpapers";
      };
      clone = pkgs.writeShellApplication {
        name = "bootstrap-repo";
        runtimeInputs = with pkgs; [
          coreutils
          openssh
          git
        ];
        text = builtins.readFile ./bootstrap-repo.sh;
      };
      bootstrap = pkgs.writeShellApplication {
        name = "bootstrap-repos";
        runtimeInputs = [ pkgs.coreutils ];
        text =
          "failed=0\n"
          + lib.concatStringsSep "\n" (
            lib.mapAttrsToList (rel: url: ''
              dest="$HOME/${rel}"
              ready=0
              # user services cannot wait on the system's network-online target.
              for attempt in $(seq 1 30); do
                if ${clone}/bin/bootstrap-repo "$dest" "${url}"; then
                  ready=1
                  break
                fi
                [ ! -e "$dest" ] && [ ! -L "$dest" ] || break
                [ "$attempt" -lt 30 ] || break
                echo "bootstrap-repos: retrying ${url} in 10s"
                sleep 10
              done
              if [ "$ready" -eq 0 ]; then
                echo "bootstrap-repos: failed to prepare $dest" >&2
                failed=1
              fi
            '') repos
          )
          + "\nexit \"$failed\"";
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
