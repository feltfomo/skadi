{
  den.aspects.cpuid-hypervisor.nixos =
    { config, pkgs, ... }:
    let
      cpuid-fault-emulation = config.boot.kernelPackages.callPackage (
        {
          stdenv,
          unzip,
          kernel,
        }:
        stdenv.mkDerivation {
          pname = "cpuid-fault-emulation";
          version = "0.1";

          # source.zip is binary and stays outside notion sync, so add it to git by hand.
          src = ../../pkgs/cpuid-fault-emulation/source.zip;

          # source.zip has no top-level directory.
          sourceRoot = ".";

          nativeBuildInputs = [ unzip ] ++ kernel.moduleBuildDependencies;

          # the vendored makefile expects a mutable /lib/modules tree.
          postPatch = ''
            substituteInPlace Makefile \
              --replace-fail '/lib/modules/$(KERNEL)/build' '${kernel.dev}/lib/modules/${kernel.modDirVersion}/build'
          '';

          # kernel.makeFlags carries O= and --eval values that break this external module build.
          makeFlags = kernel.commonMakeFlags;
          enableParallelBuilding = true;

          # kbuild leaves the module at the source root.
          installPhase = ''
            runHook preInstall
            install -Dm444 cpuid_fault_emulation.ko \
              "$out/lib/modules/${kernel.modDirVersion}/updates/cpuid_fault_emulation.ko"
            runHook postInstall
          '';
        }
      ) { };
    in
    {
      # disabling umip weakens userspace hardening, so this stays khion-only.
      boot.kernelParams = [ "clearcpuid=514" ];

      boot.extraModulePackages = [ cpuid-fault-emulation ];

      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "hypervisor";
          # sudo and modprobe must resolve through the system setuid wrappers.
          runtimeInputs = [ ];
          text = builtins.readFile ../../scripts/hypervisor.sh;
        })
      ];
    };
}
