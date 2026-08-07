{
  den.aspects.cpuid-hypervisor.nixos =
    { config, pkgs, ... }:
    let
      # out-of-tree kernel module, built via callPackage off kernelPackages so
      # it tracks this host's kernel.
      cpuid-fault-emulation = config.boot.kernelPackages.callPackage (
        {
          stdenv,
          unzip,
          kernel,
        }:
        stdenv.mkDerivation {
          pname = "cpuid-fault-emulation";
          version = "0.1";

          # git add this by hand: it's binary, so it won't sync as a page and
          # the flake won't see it untracked.
          src = ../../pkgs/cpuid-fault-emulation/source.zip;

          # the zip unpacks flat (no top-level dir), so pin the source root.
          sourceRoot = ".";

          nativeBuildInputs = [ unzip ] ++ kernel.moduleBuildDependencies;

          # repoint the Makefile's hardcoded /lib/modules/$(KERNEL)/build at the
          # store kernel tree (both its build recipe and its gcc/clang grep).
          postPatch = ''
            substituteInPlace Makefile \
              --replace-fail '/lib/modules/$(KERNEL)/build' '${kernel.dev}/lib/modules/${kernel.modDirVersion}/build'
          '';

          # no kernel.makeFlags -- its O=/--eval flags are for the kernel's own
          # build and break the module build. toolchain: moduleBuildDependencies.
          enableParallelBuilding = true;

          # kbuild drops the .ko in the source root; install to /updates per
          # dkms.conf.
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
      # 514 = CPUID_7_ECX bit 2 = UMIP. disabling it weakens userspace
      # hardening, so khion-only.
      boot.kernelParams = [ "clearcpuid=514" ];

      boot.extraModulePackages = [ cpuid-fault-emulation ];

      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "hypervisor";
          # no runtimeInputs: sudo/modprobe must be the system setuid wrappers.
          runtimeInputs = [ ];
          text = builtins.readFile ../../scripts/hypervisor.sh;
        })
      ];
    };
}
