{ inputs, lexicon, ... }:
{
  # the repository is private, so nix fetches it over ssh
  flake-file.inputs.pinax = {
    url = "git+ssh://git@github.com/feltfomo/pinax";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.pinax = lexicon {
    package = pkgs: inputs.pinax.packages.${pkgs.stdenv.hostPlatform.system}.default;
    homeManager =
      { pkgs, ... }:
      {
        # a unit lets a rebuild replace the running service, which `pinax toggle` never would
        systemd.user.services.pinax = {
          Unit.Description = "Pinax desktop panel";
          Service = {
            ExecStart = "${inputs.pinax.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/pinax serve";
            # wl-copy stays in this cgroup to serve the clipboard, and has to survive a restart
            KillMode = "process";
            # the UI watchdog exits nonzero, and `pinax quit` should stay quit
            Restart = "on-failure";
            RestartSec = 1;
          };
        };
      };
  };
}
