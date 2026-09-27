{
  pkgs,
  src,
  proxy,
}:
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "minecraft-modding-mcp";
  version = "0.1.0";
  inherit src;

  pnpmDeps = pkgs.fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pkgs.pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-lR7s5G0lT4gZ9kH2w8dG6r0y7s0M6j1Y7r0c8x5p3E=";
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
    cp -r build node_modules package.json $out/lib/minecraft-modding-mcp/
    makeWrapper ${proxy}/bin/mcp-proxy $out/bin/minecraft-modding-mcp \
      --add-flags "--server stream --stateless --no-eventStore --host 127.0.0.1 --port 8091" \
      --add-flags "--connectionTimeout 300000 --requestTimeout 900000" \
      --add-flags "-- ${pkgs.nodejs_24}/bin/node $out/lib/minecraft-modding-mcp/build/index.js"
    runHook postInstall
  '';
})
