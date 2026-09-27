{
  pkgs,
  src,
  proxy,
  configFile,
}:
pkgs.buildNpmPackage {
  pname = "desktop-commander";
  version = "0.2.47";

  inherit src;

  npmDepsHash = "sha256-o0wYr4lV3G6H2R3m4rRzN0n8l1i3m5o2e7Q4y0Z7v2I=";
  makeCacheWritable = true;

  nativeBuildInputs = with pkgs; [
    bun
    makeWrapper
    nodejs_24
  ];

  postPatch = ''
    cp ${configFile} config.json
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/desktop-commander
    cp -r dist node_modules package.json $out/lib/desktop-commander/
    makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/desktop-commander \
      --add-flags $out/lib/desktop-commander/dist/index.js
    # keep the http bridge next to the server so the systemd unit can spawn it
    ln -s ${proxy}/bin/mcp-proxy $out/bin/mcp-proxy
    runHook postInstall
  '';
}
