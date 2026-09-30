{
  lib,
  stdenv,
  buildNpmPackage,
  nodejs_24,
  keyutils,
  autoPatchelfHook,
  makeWrapper,
  zlib,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./package.json);
in
buildNpmPackage {
  pname = manifest.name;
  inherit (manifest) version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };

  nodejs = nodejs_24;
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-iiM7Z/ECpfR5tOx04etYOdXX2s7bkGWvrPQazxL8j7o=";
  # Pi supplies its own API packages; peers must not install a second runtime.
  npmFlags = [
    "--legacy-peer-deps"
    "--ignore-scripts"
  ];
  dontNpmBuild = true;
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp -r node_modules package.json package-lock.json "$out/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pi-mcp-adapter" \
      --add-flags "$out/node_modules/pi-mcp-adapter/cli.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_24
          keyutils
        ]
      }
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node - <<'JS'
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const { createRequire } = require("node:module");
    const root = process.env.out;
    const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
    for (const [name, version] of Object.entries(manifest.dependencies)) {
      const installed = JSON.parse(fs.readFileSync(path.join(root, "node_modules", name, "package.json"), "utf8"));
      assert.equal(installed.version, version);
    }
    for (const entry of manifest.pi.extensions) fs.accessSync(path.join(root, entry));
    const native = createRequire(path.join(root, "package.json"))("@napi-rs/keyring");
    assert.equal(typeof native.Entry, "function");
    console.log("2 pinned Pi extensions and the Linux keyring binding verified");
    JS
    runHook postInstallCheck
  '';

  meta = {
    description = "Pinned Pi Web Access and MCP Adapter extensions";
    platforms = lib.platforms.linux;
  };
}
