{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      targets = inputs.self.lib.${system};
      canonical = inputs.self.nixosConfigurations.khion.config;
      full = (targets.mkInstallTarget { host = "khion"; }).config;
      filtered =
        (targets.mkInstallTarget {
          host = "khion";
          drop = [
            "gpu-nvidia"
            "steam"
          ];
        }).config;
      keepsUser =
        config:
        config.home-manager.users.feltfomo.home.username == "feltfomo"
        && config.home-manager.users.feltfomo.programs.fish.enable
        && config.sops.secrets.feltfomo-password.neededForUsers
        && config.users.users.feltfomo.hashedPasswordFile == config.sops.secrets.feltfomo-password.path;
      keepsBase =
        config:
        config.skadi.installer == canonical.skadi.installer
        && config.fileSystems."/persist".neededForBoot
        && config.lexicon.furnish.enable;
      invalid = builtins.tryEval (
        builtins.deepSeq
          (targets.mkInstallTarget {
            host = "khion";
            drop = [ "unknown-install-aspect" ];
          }).config.skadi.installer
          true
      );
      checks = {
        menu = builtins.all (name: builtins.elem name targets.hostAspects.khion) [
          "base"
          "gpu-nvidia"
          "steam"
        ];
        full = full.programs.steam.enable && builtins.elem "nvidia" full.services.xserver.videoDrivers;
        filtered =
          !filtered.programs.steam.enable && !(builtins.elem "nvidia" filtered.services.xserver.videoDrivers);
        users = keepsUser full && keepsUser filtered;
        base = keepsBase full && keepsBase filtered;
        invalidDrop = !invalid.success;
        canonical =
          canonical.programs.steam.enable && builtins.elem "nvidia" canonical.services.xserver.videoDrivers;
      };
      failures = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        installer-targets =
          assert lib.assertMsg (
            failures == [ ]
          ) "installer target integration failed: ${lib.concatStringsSep ", " failures}";
          pkgs.runCommandLocal "installer-targets-check" { } ''
            touch "$out"
          '';
      };
    };
}
