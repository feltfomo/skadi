# Thin, stable-pinned reinstall ISO for the skadi fleet.
# Pinned to nixos-26.05 (inputs.nixpkgs-stable), independent of the unstable
# channel the fleet tracks. Build:
#   nix build .#nixosConfigurations.installer.config.system.build.isoImage
# then flash result/iso/*.iso in DD/raw mode (Rufus DD, Etcher, Caligula) --
# ISO-mode / Ventoy break the by-label device (see frictions log #1).
{ inputs, ... }:
{
  # installer pins to stable 26.05 while the fleet tracks unstable: den's
  # per-host `instantiate` is meant to be overridden for exactly this, keeping
  # the ISO reproducible. output still lands at nixosConfigurations.installer.
  den.hosts.x86_64-linux.installer.instantiate = inputs.nixpkgs-stable.lib.nixosSystem;

  den.aspects.installer.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # match the disko CLI to the disko module the fleet configs use,
      # so `disko --mode ... --flake` agrees with the host's disko.devices.
      # Rebuilt against Lix (config.nix.package): the fleet's flake.lock is
      # Lix-dialect, but disko's wrapper otherwise bundles the CppNix from
      # nixpkgs, so `disko --flake` evaluates the lock with CppNix and dies
      # on "mismatch in field 'url'". The system Lix reads the lock fine
      # (verified with `nix flake metadata`), so point disko at it too.
      disko = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko.override {
        nix = config.nix.package;
      };

      # skadi-install lives in the repo (scripts/skadi-install.sh) and is
      # baked into the ISO as a first-class command.
      skadi-install = pkgs.writeShellApplication {
        name = "skadi-install";
        runtimeInputs = [
          # Lix first so nixos-install (step 3) also evaluates the
          # Lix-dialect lock with Lix, not a CppNix picked up from PATH.
          config.nix.package
          disko
        ]
        ++ (with pkgs; [
          git
          sops
          ssh-to-age
          age
          mkpasswd
          jq
          curl
          nixos-install-tools
          util-linux
          openssh
        ]);
        text = builtins.readFile ../scripts/skadi-install.sh;
      };
    in
    {
      imports = [
        (inputs.nixpkgs-stable + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
        # Lix, matching the fleet. flake.lock is written by Lix, so the ISO's
        # nix/disko/nixos-install must also be Lix -- otherwise getFlake rejects
        # the lock ("mismatch in field 'url'" on the git.lix.systems tarball
        # inputs, which carry Lix's __final/?rev= dialect). Stays thin otherwise:
        # just the Nix impl, no base/home-manager/desktop.
        inputs.lix-module.nixosModules.default
      ];

      networking.hostName = "skadi-installer";

      # NetworkManager so `nmtui` works for the laptop; LAN is automatic.
      # NO wifi PSK is baked in -> nothing wifi-related leaks through the
      # Notion mirror. For lumi: run `nmtui` once at install time.
      networking.networkmanager.enable = true;
      networking.wireless.enable = lib.mkForce false;

      # remote install over ssh with your key only, no passwords.
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKAWZ+4L7E0osgTA8eybrsmUoTUtBSzEaE4ytD+rcPO 241195017+feltfomo@users.noreply.github.com"
        # Throwaway keypair the VM harness uses to drive an unattended install on
        # a disposable localhost VM. The private half lives in ~/.cache/skadi-vm
        # (never committed) and guards nothing real: the VM has no network and
        # keeps the placeholder token.
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElUx+G8NdV6W0NVEh3wpOg33mBnHY0oG9b31eds/LSs skadi-vm-test"
      ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        # Build the fleet closure the way khion does: nix-daemon + stock
        # nixbld users + sandbox on. The old ISO built as root via
        # `--store local` with the sandbox off, which cascaded into pasta/
        # userns FOD failures ("sandbox network setup timed out") and
        # /homeless-shelter purity breaks. sandbox already defaults on, but
        # pin it so a stray `--option sandbox false` can't quietly flip it.
        # userns is available on the live ISO, so daemon nixbld builds get a
        # real one and FODs work.
        sandbox = true;

        # Cache the third-party upstreams we don't build ourselves: the base
        # closure (cache.nixos.org, always hits) and the desktop projects
        # (Hyprland/walker/noctalia). These are OPPORTUNISTIC -- each input
        # follows our nixpkgs, so when our pin diverges from what upstream
        # published to their cachix the derivation hash misses and they build
        # from source anyway (expected, seen in practice; not a failure).
        # Building them from source via `nix build` is fine -- the
        # `src = fs.gitTracked` "not a local working tree of a Git repository"
        # error only bites `nixos-install --flake` (re-evals in a git-less
        # /mnt); the two-step build in skadi-install.sh avoids it. So these
        # caches are speed-when-they-hit, NOT load-bearing. Also in flake.nix's
        # nixConfig (via accept-flake-config below); listed here too so the
        # install doesn't lean on that acceptance.
        #
        # Lix is NOT cached, and wouldn't hit anyway: we pin Lix HEAD
        # (inputs.lix = .../main.tar.gz, a -dev build) and compile it against
        # our nixpkgs, so the derivation doesn't match upstream's own
        # cache.lix.systems builds -- it compiles from source every install
        # (verified: the VM builds lix-*-dev from source even with
        # cache.lix.systems still trusted). That's fine and wanted: its
        # doubled-debuginfo cargo/C++ target is the biggest from-source
        # derivation and the exact disk-pressure canary that ENOSPC'd the VM,
        # so it's what actually exercises build-dir=/mnt + --max-jobs 1 + GC
        # below. Leaving cache.lix.systems out just makes that explicit -- no
        # phantom safety net. Fleet code (notion-sync, the configs, the
        # closure assembly) is never cached either.
        substituters = [
          "https://cache.nixos.org"
          "https://hyprland.cachix.org"
          "https://walker.cachix.org"
          "https://walker-git.cachix.org"
          "https://noctalia.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
          "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
          "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        ];

        # Daemon build scratch on the target disk, not the ISO's tmpfs
        # (default build-dir=/nix/var/nix/b lives on the RAM store). Once the
        # build runs through the daemon instead of `--store local`, the
        # client's TMPDIR no longer reaches the builder -- startBuilder()
        # unpacks into settings.build-dir, and its only fallback is the
        # daemon's own /tmp (tmpfs -> OOM). The daemon createDirs() this
        # itself on first build; /mnt just has to exist (true after disko
        # mounts) and be on disk.
        build-dir = "/mnt/nix-build-tmp";

        # Trust the fleet flake's declared binary caches (hyprland / walker /
        # noctalia) so nixos-install SUBSTITUTES the desktop closure rather
        # than compiling it from source. This is how these flakes are meant
        # to be consumed -- and it sidesteps upstream Hyprland's
        # `src = fs.intersection (fs.gitTracked ../.) ...` (nix/default.nix),
        # which throws "not a local working tree of a Git repository"
        # whenever Hyprland is built from source from a .git-less flake
        # input -- exactly what nixos-install does on a fresh /mnt. Trusting
        # the cache means that from-source branch never runs. accept-flake-
        # config also drops the interactive "allow these settings?" prompt so
        # an unattended skadi-install run needs no keypress.
        accept-flake-config = true;
      };

      environment.systemPackages = [
        skadi-install
        disko
      ]
      ++ (with pkgs; [
        git
        sops
        ssh-to-age
        age
        mkpasswd
        jq
        curl
        neovim
      ]);

      # pin to the ISO's channel; unrelated to the fleet's stateVersion.
      # den.default pins the fleet to 25.11; the installer sets the ISO's own
      # channel explicitly. mkForce because den.default already defines it.
      system.stateVersion = lib.mkForce "26.05";
    };
}
