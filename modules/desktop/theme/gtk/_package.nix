{
  lib,
  stdenvNoCC,
  dart-sass,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-gtk-theme";
  version = "2.0.0";
  src = ./scss;
  nativeBuildInputs = [ dart-sass ];

  buildPhase = ''
    runHook preBuild
    for version in 3 4; do
      # deprecated sass syntax fails the build instead of breaking silently on a sass upgrade
      sass --no-source-map --style=expanded --no-charset \
        --fatal-deprecation=import \
        --fatal-deprecation=global-builtin \
        --fatal-deprecation=if-function \
        "gtk$version.scss" "gtk$version.css"
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    theme="$out/share/themes/Skadi"
    mkdir -p "$theme/common" "$theme/gtk-3.0" "$theme/gtk-4.0" "$out/bin" "$out/libexec"
    cp -r assets gtk3.css gtk4.css palette-dark.css palette-light.css "$theme/common/"
    for version in 3 4; do
      for variant in dark light; do
        # the palette comes first so the reactive palette can redefine it later in the same provider
        printf '@import url("../common/palette-%s.css");\n@import url("../common/gtk%s.css");\n' \
          "$variant" "$version" > "$theme/gtk-$version.0/gtk-$variant.css"
      done
      cp "$theme/gtk-$version.0/gtk-dark.css" "$theme/gtk-$version.0/gtk.css"
    done
    cat > "$theme/index.theme" <<'EOF'
    [Desktop Entry]
    Type=X-GNOME-Metatheme
    Name=Skadi

    [X-GNOME-Metatheme]
    GtkTheme=Skadi
    EOF
    cp ${./config/apply.py} "$out/libexec/skadi-gtk-apply.py"
    cat > "$out/bin/skadi-gtk-apply" <<EOF
    #!${stdenvNoCC.shell}
    set -euo pipefail
    exec ${python3}/bin/python "$out/libexec/skadi-gtk-apply.py" --theme "$out" "\$@"
    EOF
    chmod +x "$out/bin/skadi-gtk-apply"
    runHook postInstall
  '';

  meta = {
    description = "Skadi reactive GTK component theme";
    platforms = lib.platforms.linux;
  };
}
