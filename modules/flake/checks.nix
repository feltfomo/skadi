{ inputs, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    let
      binds = import ../../configs/desktop/binds.nix { inherit (pkgs) lib; };
      generated = pkgs.writeText "shared-binds.lua" binds.hyprland;
      lumiBinds = import ../../configs/desktop/binds.nix {
        inherit (pkgs) lib;
        hostName = "lumi";
      };
      lumiGenerated = pkgs.writeText "lumi-shared-binds.lua" lumiBinds.hyprland;
      apiChecked = import ../../tests/bindings-api.nix { inherit (pkgs) lib; };
      python = pkgs.python3.withPackages (packages: [ packages.tomlkit ]);
      noctaliaFiles = builtins.filter (
        entry: pkgs.lib.hasPrefix "/home/feltfomo/.config/noctalia/" entry.filesystemIdentity.destination
      ) inputs.self.nixosConfigurations.khion.config.lexicon.furnish.manifestData;
      noctaliaSources = builtins.filter pkgs.lib.isDerivation (
        map (entry: entry.source.value) (
          builtins.filter (
            entry: pkgs.lib.hasPrefix ".config/noctalia/" entry.destination
          ) inputs.self.nixosConfigurations.khion.config.lexicon.furnish.declarations
        )
      );
    in
    {
      # build both hosts so a broken config fails the check
      checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        portal-startup =
          pkgs.runCommand "portal-startup-check"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.systemd
              ];
            }
            ''
              set -euo pipefail
              python ${../../tests/portal-startup.py} ${inputs.self.nixosConfigurations.khion.pkgs.xdg-desktop-portal}/share/systemd/user/xdg-desktop-portal.service
              touch "$out"
            '';
        noctalia-config =
          pkgs.runCommand "noctalia-config-check"
            {
              # furnish retains generated sources separately from its content snapshots.
              inherit noctaliaSources;
            }
            ''
              set -euo pipefail
              mkdir -p config
              ${pkgs.lib.concatMapStringsSep "\n" (
                entry:
                let
                  destination = pkgs.lib.removePrefix "/home/feltfomo/.config/noctalia/" entry.filesystemIdentity.destination;
                in
                ''
                  mkdir -p ${pkgs.lib.escapeShellArg ("config/" + builtins.dirOf destination)}
                  cp ${pkgs.lib.escapeShellArg entry.target.path} ${pkgs.lib.escapeShellArg ("config/" + destination)}
                ''
              ) noctaliaFiles}
              for profile in hyprland mangowm; do
                validation="$(${
                  import ../../lib/noctalia-package.nix { inherit inputs pkgs; }
                }/bin/noctalia config validate "config/profiles/$profile/noctalia")"
                printf '%s\n' "$validation"
                if printf '%s\n' "$validation" | ${pkgs.gnugrep}/bin/grep -Eq 'unrecognized widget type|no loaded plugin with this id'; then
                  exit 1
                fi
              done
              touch $out
            '';
        desktop-binds =
          assert apiChecked;
          pkgs.runCommand "desktop-binds-check" { } ''
            set -euo pipefail
            ${pkgs.lua}/bin/lua ${../../tests/desktop-binds.lua} ${../..} ${generated} khion
            ${pkgs.lua}/bin/lua ${../../tests/desktop-binds.lua} ${../..} ${lumiGenerated} lumi
            ${python}/bin/python ${../../tests/noctalia-session.py} ${../../scripts/noctalia-session.py}
            touch $out
          '';
        khion = inputs.self.nixosConfigurations.khion.config.system.build.toplevel;
        lumi = inputs.self.nixosConfigurations.lumi.config.system.build.toplevel;
      };
    };
}
