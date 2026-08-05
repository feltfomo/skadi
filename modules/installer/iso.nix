# thin, stable-pinned reinstall iso for the skadi fleet. pinned to nixos-26.05
# (inputs.nixpkgs-stable), independent of the unstable channel the fleet tracks.
# build.
#   nix build .#nixosConfigurations.installer.config.system.build.isoImage
# then flash result/iso/*.iso in dd/raw mode (rufus dd, etcher, caligula) --
# iso-mode / ventoy break the by-label device (see frictions log #1).
{ inputs, ... }:
{
  # installer pins to stable 26.05 while the fleet tracks unstable. den's per-host
  # instantiate is meant to be overridden for exactly this. output still lands at
  # nixosConfigurations.installer.
  den.hosts.x86_64-linux.installer.instantiate = inputs.nixpkgs-stable.lib.nixosSystem;

  den.aspects.installer.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # match the disko cli to the fleet's disko module so `disko --flake` agrees
      # with the host's disko.devices. rebuilt against lix (config.nix.package). the
      # flake.lock is lix-dialect, but disko otherwise bundles cppnix and dies on
      # "mismatch in field 'url'" evaluating the lock.
      disko = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko.override {
        nix = config.nix.package;
      };

      # skadi-install lives in scripts/skadi-install.sh, baked into the iso as a command.
      skadi-install = pkgs.writeShellApplication {
        name = "skadi-install";
        runtimeInputs = [
          # lix first so nixos-install also evaluates the lix-dialect lock with lix,
          # not a cppnix picked up from PATH.
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
        text = builtins.readFile ../../scripts/skadi-install.sh;
      };
    in
    {
      imports = [
        (inputs.nixpkgs-stable + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
        # lix, matching the fleet. flake.lock is written by lix, so the iso's
        # nix/disko/nixos-install must also be lix or getFlake rejects the lock
        # ("mismatch in field 'url'" on the git.lix.systems inputs). thin otherwise.
        # just the nix impl, no base/home-manager/desktop.
        inputs.lix-module.nixosModules.default
      ];

      networking.hostName = "skadi-installer";

      # networkmanager so nmtui works for the laptop; lan is automatic. no wifi psk
      # is baked in so nothing wifi-related leaks through the notion mirror. for
      # lumi run nmtui once at install time.
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
        # throwaway keypair the vm harness uses for unattended installs on a
        # disposable localhost vm. private half lives in ~/.cache/skadi-vm (never
        # committed) and guards nothing real. the vm has no network and keeps the
        # placeholder token.
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElUx+G8NdV6W0NVEh3wpOg33mBnHY0oG9b31eds/LSs skadi-vm-test"
      ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        # build the fleet closure like khion. daemon + stock nixbld users + sandbox
        # on, so fods get a real userns (pasta works) and builds stay pure. sandbox
        # defaults on but pin it so a stray --option sandbox false can't flip it.
        sandbox = true;

        # cache the third-party upstreams we don't build. base (cache.nixos.org)
        # and the desktop projects (hyprland/walker/noctalia). opportunistic --
        # each follows our nixpkgs, so when our pin diverges from upstream's cachix
        # the hash misses and they build from source anyway, which is fine (the
        # gitTracked error only bites nixos-install --flake, which the two-step
        # build in skadi-install.sh avoids).
        #
        # lix is deliberately not cached and wouldn't hit anyway. we pin lix head
        # and compile against our nixpkgs, so it builds from source every install.
        # that's wanted -- its doubled-debuginfo cargo/c++ target is the biggest
        # from-source derivation and the disk-pressure canary that enospc'd the vm,
        # so it exercises build-dir=/mnt + --max-jobs 1 + gc below. fleet code isn't
        # cached either.
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

        # daemon build scratch on the target disk, not the iso's tmpfs. the client
        # tmpdir doesn't reach the daemon builder (it unpacks into build-dir, whose
        # only fallback is the daemon's own tmpfs /tmp -> oom). the daemon createDirs
        # this on first build; /mnt just has to exist and be on disk.
        build-dir = "/mnt/nix-build-tmp";

        # accept-flake-config trusts the fleet flake's declared caches so the
        # desktop closure substitutes instead of building, and drops the interactive
        # "allow these settings?" prompt so an unattended run needs no keypress.
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

      # the iso's own channel, unrelated to the fleet's stateVersion. mkForce
      # because den.default already defines it.
      system.stateVersion = lib.mkForce "26.05";
    };
}
