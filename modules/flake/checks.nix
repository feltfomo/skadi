{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # build both hosts so a broken config fails the check
      checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
        khion = inputs.self.nixosConfigurations.khion.config.system.build.toplevel;
        lumi = inputs.self.nixosConfigurations.lumi.config.system.build.toplevel;
      };
    };
}
