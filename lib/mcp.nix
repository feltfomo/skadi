{ lib }:
let
  hardening = {
    CapabilityBoundingSet = "";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = "tmpfs";
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    UMask = "0077";
  };

  mkProxyPackage =
    { pkgs, source }:
    pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "mcp-proxy";
      version = "6.7.11";
      src = source;
      postPatch = ''
        node <<'EOF'
        const fs = require('fs');
        const path = 'src/startHTTPServer.ts';
        const source = fs.readFileSync(path, 'utf8');
        const getStart = source.indexOf('  if (\n    req.method === "GET" &&');
        const lastEvent = source.indexOf('    const lastEventId', getStart);
        if (getStart < 0 || lastEvent < 0) {
          throw new Error('could not locate Streamable HTTP GET handler');
        }
        const before = '      res.writeHead(400).end("No active transport");';
        const after = '      res.writeHead(404).end("Session not found");';
        const block = source.slice(getStart, lastEvent);
        if (block.split(before).length !== 2) {
          throw new Error('unexpected stale-session response shape');
        }
        fs.writeFileSync(
          path,
          source.slice(0, getStart) + block.replace(before, after) + source.slice(lastEvent),
        );
        EOF
      '';

      pnpmDeps = pkgs.fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        pnpm = pkgs.pnpm_10;
        fetcherVersion = 3;
        hash = "sha256-2M5kSUQP2pEDjL46Ixvwv0QRz/hLTELSZV0p7OICLwU=";
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
        mkdir -p $out/bin $out/lib/mcp-proxy
        cp -r dist node_modules package.json $out/lib/mcp-proxy/
        makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/mcp-proxy \
          --add-flags $out/lib/mcp-proxy/dist/bin/mcp-proxy.mjs
        runHook postInstall
      '';
    });

  mkStdioService =
    {
      proxy,
      description,
      port,
      command,
      user ? "feltfomo",
      group ? "users",
      workingDirectory,
      stateDirectory,
      environment ? { },
      path ? [ ],
      readOnlyPaths ? [ ],
      readWritePaths ? [ ],
      inaccessiblePaths ? [ ],
      networkAccess ? true,
      memoryHigh ? "2G",
      memoryMax ? "4G",
      tasksMax ? 512,
      extraServiceConfig ? { },
    }:
    {
      inherit description;
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      inherit environment path;

      serviceConfig =
        hardening
        // {
          User = user;
          Group = group;
          WorkingDirectory = workingDirectory;
          StateDirectory = stateDirectory;
          StateDirectoryMode = "0700";
          ExecStart = lib.escapeShellArgs (
            [
              "${proxy}/bin/mcp-proxy"
              "--server"
              "stream"
              "--stateless"
              "--no-eventStore"
              "--host"
              "127.0.0.1"
              "--port"
              (toString port)
              "--connectionTimeout"
              "300000"
              "--requestTimeout"
              "900000"
              "--"
            ]
            ++ command
          );
          Restart = "on-failure";
          RestartSec = "2s";
          KillMode = "mixed";
          OOMPolicy = "continue";
          MemoryAccounting = true;
          MemoryHigh = memoryHigh;
          MemoryMax = memoryMax;
          TasksMax = tasksMax;
          TimeoutStopSec = "15s";
          BindReadOnlyPaths = readOnlyPaths;
          BindPaths = readWritePaths;
          InaccessiblePaths = inaccessiblePaths;
        }
        // lib.optionalAttrs (!networkAccess) {
          IPAddressAllow = "localhost";
          IPAddressDeny = "any";
        }
        // extraServiceConfig;
    };
in
{
  inherit hardening mkProxyPackage mkStdioService;
}
