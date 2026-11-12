{
  lib,
  stdenvNoCC,
  dart-sass,
  nushell,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-theme-design";
  version = "1.0.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./scss
      ./tests
      ./skadi-sass.nu
    ];
  };

  buildPhase = ''
    runHook preBuild
    substitute skadi-sass.nu skadi-sass \
      --replace-fail @nu@ ${lib.getExe nushell} \
      --replace-fail @sass@ ${lib.getExe dart-sass} \
      --replace-fail @share@ "$out/share/sass"
    chmod +x skadi-sass
    runHook postBuild
  '';

  doCheck = true;
  # each fail case must stop the build, proving its guard still fires.
  checkPhase = ''
    runHook preCheck
    export SKADI_SASS_LOAD_PATH=scss
    for test in tests/*.scss; do
      ./skadi-sass "$test" /dev/null
    done
    for test in tests/fail/*.scss; do
      if ./skadi-sass "$test" /dev/null 2>/dev/null; then
        echo "$test compiled, but it must fail" >&2
        exit 1
      fi
    done
    unset SKADI_SASS_LOAD_PATH
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/sass"
    cp -r scss/skadi "$out/share/sass/"
    install -Dm755 skadi-sass "$out/bin/skadi-sass"
    runHook postInstall
  '';

  meta = {
    description = "Skadi's shared theme roles, metrics and material recipes, and the sass that builds on them";
    mainProgram = "skadi-sass";
    platforms = lib.platforms.all;
  };
}
