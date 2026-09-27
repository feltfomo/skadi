{
  inputs,
  pkgs,
}:
let
  desktopCommander = pkgs.buildNpmPackage {
    pname = "desktop-commander";
    version = "0.2.47";
    src = inputs.desktop-commander;
    npmDeps = pkgs.importNpmLock { npmRoot = inputs.desktop-commander; };
    npmConfigHook = pkgs.importNpmLock.npmConfigHook;
    npmRebuildFlags = [ "--ignore-scripts" ];
    dontCheckForBrokenSymlinks = true;
    postConfigure = ''
      find -path "*@vscode/ripgrep" -type d \
        -execdir mkdir -p {}/bin \; \
        -execdir ln -sf ${pkgs.ripgrep}/bin/rg {}/bin/rg \;
    '';
  };
  minecraftSource = pkgs.fetchFromGitHub {
    owner = "adhi-jp";
    repo = "minecraft-modding-mcp";
    rev = "f9947bfcbc8a055d1d6d3de09ebaf62f3eb2e7b3";
    hash = "sha256-c/7DEKCX92thWBMH7GouIO0iS0P4yiKq7SMX3vSQB/4=";
  };
  minecraftModding = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "minecraft-modding-mcp";
    version = "7.0.0-rc.1";
    src = minecraftSource;
    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      pnpm = pkgs.pnpm_10;
      fetcherVersion = 3;
      hash = "sha256-mT05VPQh3TRzbHaEoN3H7+RHnIBwOqDLRwFHIsWn2uA=";
    };
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.nodejs_24
      pkgs.pnpm_10
      pkgs.pnpmConfigHook
    ];
    buildPhase = ''
      runHook preBuild
      pnpm build
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/lib/minecraft-modding-mcp
      cp -r dist node_modules package.json $out/lib/minecraft-modding-mcp/
      makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/minecraft-modding-mcp \
        --add-flags $out/lib/minecraft-modding-mcp/dist/cli.js
      runHook postInstall
    '';
  });
  codebaseMemorySource = pkgs.fetchFromGitHub {
    owner = "DeusData";
    repo = "codebase-memory-mcp";
    rev = "5802ccdd77c9913f8643092839c698bad10b2c4a";
    hash = "sha256-W7697fCzfjSIuEqQgJRkLE6VBhfwK/lHO8AiKB6hYAY=";
  };
  codebaseMemory = pkgs.stdenv.mkDerivation {
    pname = "codebase-memory-mcp";
    version = "0.10.8";
    src = codebaseMemorySource;
    nativeBuildInputs = [ pkgs.gnumake ];
    buildInputs = [ pkgs.zlib ];
    buildPhase = "make -j$NIX_BUILD_CORES -f Makefile.cbm cbm";
    installPhase = "install -Dm755 build/c/codebase-memory-mcp $out/bin/codebase-memory-mcp";
  };
  serena = inputs.serena.packages.${pkgs.stdenv.hostPlatform.system}.serena;
  gradleMcpJar = pkgs.fetchurl {
    url = "https://repo1.maven.org/maven2/dev/rnett/gradle-mcp/gradle-mcp/0.0.15/gradle-mcp-0.0.15.jar";
    hash = "sha256-UeoA/aONeVBFlUwfyqL520sESH/B7lWvb+Z3g4b4R3I=";
  };
  gradleMcp = pkgs.writeShellApplication {
    name = "gradle-mcp";
    runtimeInputs = [ pkgs.jdk25 ];
    text = ''
      exec java \
        -Duser.home="$HOME" \
        -Djava.io.tmpdir="$TMPDIR" \
        -jar ${gradleMcpJar} stdio "$@"
    '';
  };
  lldbMcp = pkgs.llvmPackages_latest.lldb;
in
{
  inherit
    desktopCommander
    minecraftModding
    codebaseMemory
    serena
    gradleMcp
    lldbMcp
    ;
}
