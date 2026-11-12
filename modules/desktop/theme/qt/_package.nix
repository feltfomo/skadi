{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  skadi-theme-design,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-qt-theme";
  version = "1.0.0";
  src = ./config;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    set -euo pipefail
    runHook preInstall
    mkdir -p "$out/lib/skadi-qt-theme" "$out/bin"
    cp artwork.py compose.py Skadi.kvconfig "$out/lib/skadi-qt-theme/"
    cp ${skadi-theme-design}/share/skadi/fallback-palette.json "$out/lib/skadi-qt-theme/fallback.json"
    ${python3}/bin/python "$out/lib/skadi-qt-theme/compose.py" \
      --output "$out/share/Kvantum/Skadi"
    makeWrapper ${python3}/bin/python "$out/bin/skadi-qt-theme" \
      --add-flags "$out/lib/skadi-qt-theme/compose.py"
    runHook postInstall
  '';

  meta = {
    description = "Custom wallpaper-reactive Skadi theme for Qt Widgets";
    platforms = lib.platforms.linux;
    mainProgram = "skadi-qt-theme";
  };
}
