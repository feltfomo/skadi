{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "win10-cursors";
  version = "0-unstable-2020-07-21";

  src = fetchFromGitHub {
    owner = "yeyushengfan258";
    repo = "Win10OS-cursors";
    rev = "79d13bb90eb9346a40a2da5a1f5cb24cb919f256";
    hash = "sha256-fwnTC1jZl88orC4sBsMglmMlA2N1SlD/6qT5FBPpL4c=";
  };

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/icons/Win10OS"
    cp -a dist/. "$out/share/icons/Win10OS/"
    runHook postInstall
  '';

  meta = {
    description = "Windows-style cursor theme with an arrow and tail";
    homepage = "https://github.com/yeyushengfan258/Win10OS-cursors";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
