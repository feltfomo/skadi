{
  pkgs,
  src,
  proxy,
}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "codebase-memory-mcp";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    pkgs.gcc
    pkgs.makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    gcc -O2 -o codebase-memory-mcp main.c -lsqlite3
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp codebase-memory-mcp $out/bin/codebase-memory-mcp-server
    makeWrapper ${proxy}/bin/mcp-proxy $out/bin/codebase-memory-mcp \
      --add-flags "--server stream --stateless --no-eventStore --host 127.0.0.1 --port 8092" \
      --add-flags "--connectionTimeout 300000 --requestTimeout 900000" \
      --add-flags "-- $out/bin/codebase-memory-mcp-server"
    runHook postInstall
  '';
}
