{ pkgs, ... }:
pkgs.buildNpmPackage {
  pname = "spicetify-lucid";
  version = "unstable-2026-05-26";

  src = pkgs.fetchFromGitLab {
    owner = "sanoojes";
    repo = "spicetify-lucid";
    rev = "main";
    hash = "sha256-Yj3+opEh16aJslCT9f2GTTEwLUk9A7bO/6i+LHk/AVA=";
  };

  npmDepsHash = "sha256-eFMeAeA6J4xngWF7iKmV/DhN4gfwlbYMLRmEy1ap9v4=";

  nativeBuildInputs = with pkgs; [
    bun
    spicetify-cli
  ];

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  preConfigure = ''
    export HOME=$TMPDIR
    mkdir -p $HOME/.config/spicetify
    printf '[Setting]\nspotify_path = /dev/null\nprefs_path = /dev/null\ninject_theme_js = 1\ninject_css = 1\ncurrent_theme = Lucid\ncolor_scheme = dark\nalways_enable_devtools = 0\n[AdditionalOptions]\nexperimental_features = 0\nextensions = \ncustom_apps = \n[Backup]\nversion = \nwith = \n' > $HOME/.config/spicetify/config-xpui.ini
  '';

  buildPhase = ''
    runHook preBuild
    bun run build:theme
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp dist/user.css $out/user.css
    cp dist/theme.js $out/theme.js
    cp color.ini $out/color.ini
    cp -r assets $out/assets
    runHook postInstall
  '';

  dontNpmBuild = true;
}
