# Thin, stable-pinned reinstall ISO for the skadi fleet.
# Pinned to nixos-26.05 (inputs.nixpkgs-stable), independent of the unstable
# channel the fleet tracks. Build:
#   nix build .#nixosConfigurations.installer.config.system.build.isoImage
# then flash result/iso/*.iso in DD/raw mode (Rufus DD, Etcher, Caligula) --
# ISO-mode / Ventoy break the by-label device (see frictions log #1).
{ inputs, ... }:
{
  flake.nixosConfigurations.installer = inputs.nixpkgs-stable.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      (inputs.nixpkgs-stable + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      # Lix, matching the fleet. flake.lock is written by Lix, so the ISO's
      # nix/disko/nixos-install must also be Lix -- otherwise getFlake rejects
      # the lock ("mismatch in field 'url'" on the git.lix.systems tarball
      # inputs, which carry Lix's __final/?rev= dialect). Stays thin otherwise:
      # just the Nix impl, no base/home-manager/desktop.
      inputs.lix-module.nixosModules.default
      (
        { pkgs, lib, config, ... }:
        let
          # match the disko CLI to the disko module the fleet configs use,
          # so `disko --mode ... --flake` agrees with the host's disko.devices.
          # Rebuilt against Lix (config.nix.package): the fleet's flake.lock is
          # Lix-dialect, but disko's wrapper otherwise bundles the CppNix from
          # nixpkgs, so `disko --flake` evaluates the lock with CppNix and dies
          # on "mismatch in field 'url'". The system Lix reads the lock fine
          # (verified with `nix flake metadata`), so point disko at it too.
          disko = (inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko).override {
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
          ];

          nix.settings.experimental-features = [
            "nix-command"
            "flakes"
          ];

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
          system.stateVersion = "26.05";
        }
      )
    ];
  };
}
