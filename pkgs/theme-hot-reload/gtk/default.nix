{
  lib,
  stdenv,
  pkg-config,
  gtk3,
  gtk4,
}:
stdenv.mkDerivation {
  pname = "skadi-gtk-palette-reload";
  version = "1.1.0";
  src = ./.;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    gtk3
    gtk4
  ];
  dontConfigure = true;
  buildPhase = ''
    set -euo pipefail
    runHook preBuild
    # --as-needed keeps the module from dragging unused libraries into host processes.
    for library in gtk+-3.0 gtk4; do
      mkdir -p "$library"
      $CC -std=c11 -Wall -Wextra -shared -fPIC -Wl,--as-needed $(pkg-config --cflags "$library") \
        reload.c -o "$library/libskadi-palette-reload.so" $(pkg-config --libs "$library")
    done
    runHook postBuild
    # stdenv's later phases expect nounset to be disabled.
    set +u
  '';
  installPhase = ''
    set -euo pipefail
    runHook preInstall
    install -Dm755 gtk+-3.0/libskadi-palette-reload.so "$out/lib/gtk-3.0/modules/libskadi-palette-reload.so"
    # gtk 4 finds this through GTK_PATH, which NixOS points at every profile's lib/gtk-4.0.
    install -Dm755 gtk4/libskadi-palette-reload.so "$out/lib/gtk-4.0/4.0.0/immodules/libskadi-palette-reload.so"
    runHook postInstall
    set +u
  '';
  meta = {
    description = "Reload Skadi GTK 3 and GTK 4 palette definitions in running applications";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
