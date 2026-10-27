{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:
stdenv.mkDerivation {
  pname = "lumi-es8326-audio";
  inherit (kernel) version;
  inherit (kernel) src;
  sourceRoot = ".";
  patches = [
    ./amplifier-state.patch
    ./jack-resume.patch
  ];

  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  # kbuild signs the installed module; user-space ELF fixups must not alter it.
  dontPatchELF = true;
  dontStrip = true;

  unpackPhase = ''
    set -euo pipefail
    runHook preUnpack
    tar --extract --file "$src" --wildcards --strip-components=1 \
      '*/sound/soc/intel/boards/sof_es8336.c' \
      '*/sound/soc/intel/boards/hda_dsp_common.h' \
      '*/sound/soc/codecs/hdac_hda.h' \
      '*/sound/soc/codecs/es8326.c' \
      '*/sound/soc/codecs/es8326.h'
    runHook postUnpack
  '';

  postPatch = ''
    set -euo pipefail
    printf '%s\n' \
      'obj-m += snd-soc-sof_es8336.o' \
      'snd-soc-sof_es8336-y := sof_es8336.o' \
      > sound/soc/intel/boards/Makefile
    printf '%s\n' \
      'obj-m += snd-soc-es8326.o' \
      'snd-soc-es8326-y := es8326.o' \
      > sound/soc/codecs/Makefile
  '';

  buildPhase = ''
    set -euo pipefail
    runHook preBuild
    for directory in sound/soc/intel/boards sound/soc/codecs; do
      make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
        ${lib.escapeShellArgs kernelModuleMakeFlags} \
        "M=$PWD/$directory" modules
    done
    runHook postBuild
  '';

  installPhase = ''
    set -euo pipefail
    runHook preInstall
    for directory in sound/soc/intel/boards sound/soc/codecs; do
      make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
        ${lib.escapeShellArgs kernelModuleMakeFlags} \
        "M=$PWD/$directory" \
        "INSTALL_MOD_PATH=$out" INSTALL_MOD_DIR=updates modules_install
    done
    runHook postInstall
  '';

  meta = {
    description = "ES8326 audio drivers with amplifier and jack resume fixes";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
