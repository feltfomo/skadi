{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  lua5_4,
  fzf,
  coreutils,
  runtimeShell,
  herdr,
}:
let
  lua = lua5_4.withPackages (ps: [ ps.luv ]);
in
stdenvNoCC.mkDerivation {
  pname = "herdr-pickr";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "javoscript";
    repo = "herdr-pickr";
    rev = "a4227e8e176e58abb0a0a8aafc71a4d90d64ad5f";
    sha256 = "0wpjpi67gqxff0k42mmzpidfvlfy0f8hp3njzvh69498av8m19iw";
  };

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    lua
    fzf
  ];
  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    # The remaining upstream integration suites use Darwin's script/stty flags.
    substituteInPlace tests/test.lua \
      --replace-fail '"pane_launch.lua", "panes.lua", "columns.lua", "pty_runner_test.lua", "fzf_compat.lua", "fzf_actions.lua", "unified_fzf.lua", "live_snapshots.lua", "live_refresh.lua"' \
        '"pane_launch.lua", "panes.lua", "columns.lua", "live_snapshots.lua"'
    lua tests/test.lua
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp -r src herdr-plugin.toml LICENSE "$out/"
    makeWrapper ${lua}/bin/lua "$out/bin/herdr-pickr-lua" \
      --prefix PATH : ${
        lib.makeBinPath [
          fzf
          coreutils
          herdr
        ]
      }
    substituteInPlace "$out/herdr-plugin.toml" \
      --replace-fail '"lua", "src/' '"'"$out"'/bin/herdr-pickr-lua", "src/'
    substituteInPlace "$out/src/pickr/core.lua" \
      --replace-fail '/bin/sh -c' '${runtimeShell} -c'
    runHook postInstall
  '';

  meta = {
    description = "Herdr fuzzy pane, tab, space and agent pickers with previews";
    homepage = "https://github.com/javoscript/herdr-pickr";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = lib.platforms.linux;
  };
}
