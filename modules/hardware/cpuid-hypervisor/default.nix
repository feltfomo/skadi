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
          src = ./source.zip;

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

          # Kbuild strips before generating the module certificate; later fixups must preserve it.
          dontStrip = true;
          dontPatchELF = true;

          installPhase = ''
            runHook preInstall
            make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
              ${pkgs.lib.escapeShellArgs kernel.commonMakeFlags} \
              M="$PWD" INSTALL_MOD_PATH="$out" INSTALL_MOD_DIR=updates \
              INSTALL_MOD_STRIP=1 DEPMOD=true modules_install
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
          text = builtins.readFile ./hypervisor.sh;
        })
      ];
    };
}
