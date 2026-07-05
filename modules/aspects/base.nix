{ inputs, den, ... }:
{
  den.aspects.base = {
    includes = [
      den.aspects.system
      den.aspects.thunar
      den.aspects.impermanence
      den.aspects.graalvm-oracle-21
      den.aspects.sops
      den.aspects.provision
      den.aspects.installer-tunables
    ];

    nixos =
      { lib, pkgs, ... }:
      {
        # home-manager module for the homeManager class, lix as the nix impl.
        # hjem is wired by den, so importing its module here declares hjem-lib
        # twice. disko is imported per host, next to its disko.devices.
        imports = [
          inputs.home-manager.nixosModules.home-manager
          inputs.lix-module.nixosModules.default
        ];

        # Lix tracks HEAD (uncached), so it builds from source, which runs its
        # functional2 suite in installCheck. Two IFD golden-snapshot tests assert
        # stderr byte-for-byte and break in sandbox-less CI: GitHub runners can't
        # unshare namespaces, so Lix prepends "auto-disabling sandboxing" and the
        # lines shift. Skip Lix's own suite here; upstream Lix CI already gates it.
        nix.package = lib.mkForce (
          pkgs.lix.overrideAttrs (_: {
            doInstallCheck = false;
            doCheck = false;
          })
        );

        # home-manager runs inside the system, sharing pkgs and overlays
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs; };
      };
  };
}
