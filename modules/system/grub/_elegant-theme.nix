{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "elegant-grub-theme";
  version = "2026-10-25";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "Elegant-grub2-themes";
    rev = "f8a8d41c8f306f8bdfae41db1a425cf0a2451477";
    sha256 = "1iy7vbqap7s9bw5z0prnacd9qbmx65m1gs3b31ms30vvqrsfa8z3";
  };

  dontBuild = true;
  installPhase = ''
    set -euo pipefail
    runHook preInstall
    mkdir -p "$out"
    cp common/terminus*.pf2 common/unifont-16.pf2 "$out/"
    cp -r assets/assets-icons-dark/icons-dark-1080p "$out/icons"
    cp backgrounds/backgrounds-forest/background-forest-window-left-dark.jpg "$out/background.jpg"
    cp config/theme-window-left-dark-1080p.txt "$out/theme.txt"
    cp assets/assets-other/other-1080p/window-left-alt.png "$out/info.png"
    cp assets/assets-other/other-1080p/Default.png "$out/logo.png"
    for part in e c w; do
      cp "assets/assets-other/other-1080p/select_$part-forest-dark.png" "$out/select_$part.png"
    done
    runHook postInstall
  '';

  meta = {
    description = "Elegant Forest window left dark GRUB theme";
    homepage = "https://github.com/vinceliuice/Elegant-grub2-themes";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
