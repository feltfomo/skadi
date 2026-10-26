{
  lib,
  stdenvNoCC,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-gtk-theme";
  version = "1.0.0";
  src = ./config/theme;
  dontBuild = true;

  installPhase = ''
    set -euo pipefail
    runHook preInstall
    theme="$out/share/themes/Skadi"
    mkdir -p "$theme/common" "$theme/gtk-3.0" "$theme/gtk-4.0" "$out/bin" "$out/libexec"
    cp -r . "$theme/common/"
    for version in 3 4; do
      for variant in dark light; do
        entry="$theme/gtk-$version.0/gtk-$variant.css"
        printf '@import url("../common/palette-%s.css");\n' "$variant" > "$entry"
        for component in materials base controls views ranges popups; do
          printf '@import url("../common/%s.css");\n' "$component" >> "$entry"
        done
        printf '@import url("../common/gtk%s.css");\n' "$version" >> "$entry"
        if [ "$version" = 4 ]; then
          printf '@import url("../common/libadwaita.css");\n' >> "$entry"
        fi
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
