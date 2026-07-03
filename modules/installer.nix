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
      (
        { pkgs, lib, ... }:
        let
          # match the disko CLI to the disko module the fleet configs use,
          # so `disko --mode ... --flake` agrees with the host's disko.devices.
          disko = inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko;

          # skadi-install lives in the repo (scripts/skadi-install.sh) and is
          # baked into the ISO as a first-class command.
          skadi-install = pkgs.writeShellApplication {
            name = "skadi-install";
            runtimeInputs = [
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
