# build with nix build .#nixosConfigurations.installer.config.system.build.isoImage.
# flash result/iso/*.iso in raw mode so the filesystem label remains intact.
{ inputs, ... }:
{
  # the installer keeps its own stable package set while the fleet tracks unstable.
  flake-file.inputs.nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

  den.hosts.x86_64-linux.installer.instantiate = inputs.nixpkgs-stable.lib.nixosSystem;

  den.aspects.installer.nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # match disko's nix client to the installed lix so it can evaluate the
      # fleet's flake.lock.
      disko = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko.override {
        nix = config.nix.package;
      };

      # skadi-install lives in scripts/skadi-install.sh, baked into the iso as a command.
      skadi-install = pkgs.writeShellApplication {
        name = "skadi-install";
        runtimeInputs = [
          # use the same lix as the installer for flake evaluation.
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
      ];

      nix.package = pkgs.lixPackageSets.stable.lix;

      boot.zfs.forceImportRoot = false;
      networking.hostName = "skadi-installer";

      # use nmtui to connect lumi to wifi during installation. keep passwords out of the iso.
      networking.networkmanager.enable = true;

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
        # vm-test uses this key for unattended installs. its private key stays
        # under ~/.cache/skadi-vm, outside the repository.
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOgAOLIbgZ8Smas/KvnWNOaMzCDrZ5RFDUvQ+08MZ8Uh skadi-vm-test"
      ];

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
          "pipe-operator"
        ];

        # fixed-output builds need the sandbox's user namespace for pasta.
        sandbox = true;

        # desktop caches may miss when their nixpkgs pin differs from ours.
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

        # the daemon ignores the client's TMPDIR. put build scratch on the target
        # disk so large builds do not exhaust the iso's tmpfs.
        build-dir = "/mnt/nix-build-tmp";

        # trust the fleet's declared caches without prompting during unattended installs.
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

      # override den.default's stateVersion for the stable installer.
      system.stateVersion = lib.mkForce "26.05";
    };
}
