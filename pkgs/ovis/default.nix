{
  lib,
  stdenv,
  fetchFromGitHub,
  bun,
  bun2nixLib,
  nodejs,
  git,
  makeWrapper,
  autoPatchelfHook,
  musl,
  runtimeShell,
  herdr,
}:
let
  src = fetchFromGitHub {
    owner = "devswha";
    repo = "ovis";
    tag = "v0.4.13";
    sha256 = "029md5ckphrflhr1af1hsvi7615dr2svafbbydq7mgbpbjpwarnn";
  };
  patchedDependencies = lib.mapAttrs (
    _: path: src + "/${path}"
  ) (lib.importJSON "${src}/package.json").patchedDependencies;
in
stdenv.mkDerivation {
  pname = "ovis";
  version = "0.4.13";
  inherit src;

  nativeBuildInputs = [
    bun2nixLib.hook
    makeWrapper
    autoPatchelfHook
  ];

  # Bun installs both libc variants of the optional frontend addons.
  buildInputs = [
    stdenv.cc.cc.lib
    musl
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
    overrides = bun2nixLib.patchedDependenciesToOverrides { inherit patchedDependencies; };
    useFakeNode = false;
  };

  # Native addons must be writable copies before their NixOS library paths are patched.
  bunInstallFlags = [
    "--linker=hoisted"
    "--backend=copyfile"
  ];
  dontRunLifecycleScripts = true;
  dontUseBunBuild = true;
  dontUseBunInstall = true;

  postBunNodeModulesInstallPhase = ''
    chmod -R u+w node_modules
    autoPatchelf node_modules
  '';

  postPatch = ''
    substituteInPlace server/pty/smoke.mjs \
      --replace-fail '"/bin/sh"' '"${runtimeShell}"'
  '';

  buildPhase = ''
    runHook preBuild
    bun node_modules/vite/bin/vite.js build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/ovis" "$out/share/icons/hicolor/512x512/apps"
    cp -R dist server shared scripts node_modules package.json LICENSE \
      THIRD_PARTY_NOTICES.md "$out/lib/ovis/"
    cp public/icons/icon-512.png "$out/share/icons/hicolor/512x512/apps/ovis.png"
    makeWrapper ${lib.getExe bun} "$out/bin/ovis" \
      --chdir "$out/lib/ovis" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs
          git
          herdr
        ]
      } \
      --add-flags "$out/lib/ovis/server/index.ts"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nodejs ];
  installCheckPhase = ''
    runHook preInstallCheck
    cd "$out/lib/ovis"
    node server/pty/smoke.mjs
    test -s dist/index.html
    runHook postInstallCheck
  '';

  meta = {
    description = "Local browser client for Herdr sessions";
    homepage = "https://github.com/devswha/ovis";
    license = lib.licenses.mit;
    mainProgram = "ovis";
    platforms = lib.platforms.linux;
  };
}
