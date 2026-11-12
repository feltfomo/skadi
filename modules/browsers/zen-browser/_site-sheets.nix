{
  lib,
  stdenvNoCC,
  skadi-theme-design,
  # [ { name; documents; } ], shared with the palette reload.
  sites,
  # sheets may only use the roles this template defines.
  palette,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-zen-site-sheets";
  version = "1.0.0";
  src = lib.fileset.toSource {
    root = ./config/sites;
    fileset = ./config/sites;
  };
  nativeBuildInputs = [ skadi-theme-design ];

  buildPhase = ''
    runHook preBuild
    : > sites.css
    ${lib.concatMapStrings (site: ''
      skadi-sass --palette ${palette} ${site.name}.scss ${site.name}.css
      {
        printf '@-moz-document %s {\n' '${site.documents}'
        cat ${site.name}.css
        printf '}\n'
      } >> sites.css
    '') sites}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 sites.css "$out/sites.css"
    runHook postInstall
  '';

  meta = {
    description = "Skadi palette sheets for websites in Zen";
    platforms = lib.platforms.all;
  };
}
