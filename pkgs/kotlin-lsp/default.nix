{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  cups,
  fontconfig,
  freetype,
  glib,
  gtk3,
  libGL,
  libx11,
  libxcb,
  libxext,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  zlib,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "kotlin-lsp";
  version = "263.7084.0";

  src = fetchurl {
    url = "https://download.jetbrains.com/language-server/kotlin-server/${finalAttrs.version}/kotlin-server-${finalAttrs.version}.tar.gz";
    hash = "sha256-rgxLAeF6tzpKUienjqmebcvj5JlgAxWyJ1mk5M3dEd8=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc
    fontconfig
    libxrender
    libxrandr
    freetype
    alsa-lib
    libxext
    libxtst
    libx11
    libxcb
    libGL
    libxi
    cups
    glib
    gtk3
    zlib
  ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/kotlin-lsp" "$out/bin"
    cp -a . "$out/share/kotlin-lsp/"
    ln -s "$out/share/kotlin-lsp/bin/intellij-server" "$out/bin/kotlin-lsp"
    runHook postInstall
  '';

  # JNI libraries extracted from jars also need the C++ runtime at launch.
  postFixup = ''
    wrapProgram "$out/share/kotlin-lsp/bin/intellij-server" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          stdenv.cc.cc
          zlib
        ]
      }"
  '';

  meta = {
    description = "JetBrains Kotlin language server with its bundled runtime";
    homepage = "https://github.com/Kotlin/kotlin-lsp";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "kotlin-lsp";
  };
})
