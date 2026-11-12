{
  lib,
  stdenvNoCC,
  grub2_efi,
  imagemagick,
  librsvg,
  maple-mono,
  nixos-icons,
  nushell,
}:
stdenvNoCC.mkDerivation {
  pname = "skadi-grub-theme";
  version = "1.0.0";
  src = lib.fileset.toSource {
    root = ./grub;
    fileset = lib.fileset.unions [
      ./grub/submenu.svg
      ./grub/render.nu
    ];
  };

  buildPhase = ''
    runHook preBuild
    substitute render.nu skadi-grub-theme \
      --replace-fail @nixos_icon@ ${nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake-white.svg \
      --replace-fail @font@ ${maple-mono.NF}/share/fonts/truetype/MapleMono-NF-Regular.ttf \
      --replace-fail @submenu_icon@ "$out/share/skadi-grub-theme/submenu.svg" \
      --replace-fail @magick@ ${lib.getExe' imagemagick "magick"} \
      --replace-fail @rsvg@ ${lib.getExe' librsvg "rsvg-convert"} \
      --replace-fail @mkfont@ ${lib.getExe' grub2_efi "grub-mkfont"} \
      --replace-fail @nu@ ${lib.getExe nushell}
    chmod +x skadi-grub-theme
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 submenu.svg "$out/share/skadi-grub-theme/submenu.svg"
    install -Dm755 skadi-grub-theme "$out/bin/skadi-grub-theme"
    runHook postInstall
  '';

  meta = {
    description = "Renders Skadi's grub theme from a palette, optionally over a blurred wallpaper";
    mainProgram = "skadi-grub-theme";
    platforms = lib.platforms.linux;
  };
}
