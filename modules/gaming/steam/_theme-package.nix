{
  lib,
  stdenvNoCC,
  nodejs,
  skadi-theme-design,
  # skin.json's contents, built from the module's window list.
  skin,
  # the palette template the theme deploys beside these files.
  palette,
  # the files the theme ships, all built here.
  files,
  # web page names; theme/web/<name>.scss compiles to web/<name>.css.
  pages,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-steam-theme";
  version = "1.0.0";
  src = ./theme;
  nativeBuildInputs = [
    skadi-theme-design
    nodejs
  ];

  passAsFile = [ "skin" ];
  inherit skin;

  buildPhase = ''
    runHook preBuild
    skadi-sass --palette ${palette} theme.scss theme.css
    for page in ${lib.escapeShellArgs pages}; do
      skadi-sass --palette ${palette} "web/$page.scss" "web/$page.css"
    done
    cp "$skinPath" skin.json
    runHook postBuild
  '';

  doCheck = true;
  # tests/literal.scss compiles a hand-written color, proving the literal check still fires.
  checkPhase = ''
    runHook preCheck
    node --check recolor.js
    THEME_CSS=theme.css PALETTE=${palette} node --test recolor.test.mjs literals.test.mjs
    node literals.mjs theme.css web/*.css
    skadi-sass --palette ${palette} tests/literal.scss literal.css
    if node literals.mjs literal.css 2>/dev/null; then
      echo "tests/literal.scss passed the literal check, but it must fail" >&2
      exit 1
    fi
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    for file in ${lib.escapeShellArgs files}; do
      install -Dm444 "$file" "$out/$file"
    done
    runHook postInstall
  '';

  meta = {
    description = "Skadi's palette theme for Steam under Millennium";
    platforms = lib.platforms.all;
  };
}
