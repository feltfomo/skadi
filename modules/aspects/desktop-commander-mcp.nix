{ inputs, ... }:
{
  den.aspects.desktop-commander-mcp.nixos =
    {
      config,
      pkgs,
      ...
    }:
    let
      allowedDirectories = [
        "/home/feltfomo/Projects/axiom-nix"
        "/home/feltfomo/Projects/lexicon"
        "/etc/skadi"
        "/home/feltfomo/Projects/rime"
      ];
      # Git-aware formatters and devenv hooks need repository metadata. Keep the
      # metadata read-only, with the one nested write exception needed to install
      # project hooks when devenv enters a shell.
      readOnlyGitDirectories = map (directory: "-${directory}/.git") allowedDirectories;
      writableGitHookDirectories = map (directory: "-${directory}/.git/hooks") allowedDirectories;
      stateDirectory = "/var/lib/desktop-commander-mcp";
      configDirectory = "${stateDirectory}/.claude-server-commander";
      desktopCommanderConfig = pkgs.writeText "desktop-commander-config.json" (
        builtins.toJSON {
          inherit allowedDirectories;
          blockedCommands = [
            "adduser"
            "bcdedit"
            "chsh"
            "cipher"
            "dd"
            "diskpart"
            "fdisk"
            "firewall"
            "format"
            "grub-install"
            "halt"
            "init"
            "iptables"
            "mkfs"
            "mount"
            "net"
            "netsh"
            "nix-env"
            "nix-store"
            "nixos-rebuild"
            "parted"
            "passwd"
            "poweroff"
            "reboot"
            "reg"
            "runas"
            "sc"
            "sfc"
            "shutdown"
            "su"
            "sudo"
            "systemctl"
            "takeown"
            "umount"
            "useradd"
            "usermod"
            "visudo"
          ];
          defaultShell = "${pkgs.fish}/bin/fish";
          fileReadLineLimit = 1000;
          fileWriteLineLimit = 50;
          pendingWelcomeOnboarding = false;
          telemetryEnabled = false;
          welcomeOnboardingEligible = false;
        }
      );
      desktopCommander = pkgs.buildNpmPackage {
        pname = "desktop-commander";
        version = "0.2.47";
        src = inputs.desktop-commander;

        npmDeps = pkgs.importNpmLock {
          npmRoot = inputs.desktop-commander;
        };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        npmRebuildFlags = [ "--ignore-scripts" ];

        dontCheckForBrokenSymlinks = true;
        postConfigure = ''
          find -path "*@vscode/ripgrep" -type d \
            -execdir mkdir -p {}/bin \; \
            -execdir ln -sf ${pkgs.ripgrep}/bin/rg {}/bin/rg \;
        '';
      };
      mcpProxy = pkgs.python3Packages.buildPythonApplication {
        pname = "mcp-proxy";
        version = "0.12.0";
        src = inputs.mcp-proxy;
        pyproject = true;
        build-system = [ pkgs.python3Packages.setuptools ];
        dependencies = with pkgs.python3Packages; [
          httpx-auth
          mcp
          uvicorn
        ];
        doCheck = false;
      };
      proxyConfig = pkgs.writeText "desktop-commander-mcp-proxy.caddyfile" ''
        {
          admin off
          auto_https off
          persist_config off
        }

        :8087 {
          bind 127.0.0.1

          @authorized header Authorization "Bearer {$DESKTOP_COMMANDER_MCP_TOKEN}"
          handle @authorized {
            reverse_proxy http://127.0.0.1:8086
          }

          respond "Unauthorized" 401
        }
      '';
      inaccessiblePaths = [
        "-/etc/skadi/secrets"
        "-/etc/skadi/.notion-sync"
        "-/home/feltfomo/Projects/axiom-nix/.notion-sync"
        "-/home/feltfomo/Projects/lexicon/.notion-sync"
        "-/home/feltfomo/Projects/rime/.notion-sync"
        "-/persist"
        "-/run/secrets"
      ];
    in
    {
      sops.secrets."desktop-commander-mcp-token" = {
        owner = "feltfomo";
        mode = "0400";
      };
      skadi.provision.secrets.desktop-commander-mcp-token = {
        method = "paste";
        prompt = "DESKTOP_COMMANDER_MCP_TOKEN — generate with: openssl rand -hex 32";
        format = "DESKTOP_COMMANDER_MCP_TOKEN=%s";
      };

      environment.systemPackages = [ desktopCommander ];

      systemd.tmpfiles.rules = [
        "d ${stateDirectory} 0700 feltfomo users - -"
        "d ${configDirectory} 0700 feltfomo users - -"
        "f ${configDirectory}/config.json 0600 feltfomo users - -"
      ];

      systemd.services = {
        desktop-commander-mcp-server = {
          description = "Sandboxed Desktop Commander MCP server";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            DESKTOP_COMMANDER_DISABLE_TELEMETRY = "1";
            HOME = stateDirectory;
            SHELL = "${pkgs.fish}/bin/fish";
          };
          path = [
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.findutils
            pkgs.fish
            pkgs.gnugrep
            pkgs.gnused
            pkgs.nix
            pkgs.nodejs_22
            pkgs.python3
            pkgs.ripgrep
          ];

          serviceConfig = {
            User = "feltfomo";
            Group = "users";
            WorkingDirectory = builtins.head allowedDirectories;
            StateDirectory = "desktop-commander-mcp";
            StateDirectoryMode = "0700";
            ExecStart = "${mcpProxy}/bin/mcp-proxy --host 127.0.0.1 --port 8086 --stateless -- ${desktopCommander}/bin/desktop-commander --no-onboarding";
            Restart = "on-failure";
            RestartSec = "5s";

            CapabilityBoundingSet = "";
            # Nix evaluates and fetches flake inputs in this service process. Keep
            # AF_INET/AF_INET6 available so locked sources and binary caches work;
            # systemd IPAddressAllow accepts IP prefixes, not stable DNS names, so
            # a GitHub/Cachix hostname allowlist would break on CDN address churn.
            # The MCP and bearer-auth proxies still bind only to loopback below.
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
            BindPaths = allowedDirectories;
            BindReadOnlyPaths = [
              "${desktopCommanderConfig}:${configDirectory}/config.json"
            ];
            ReadOnlyPaths = readOnlyGitDirectories;
            ReadWritePaths = writableGitHookDirectories;
            InaccessiblePaths = inaccessiblePaths;
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
        };

        desktop-commander-mcp-auth-proxy = {
          description = "Bearer-authenticated Desktop Commander MCP proxy";
          after = [ "desktop-commander-mcp-server.service" ];
          requires = [ "desktop-commander-mcp-server.service" ];
          wantedBy = [ "multi-user.target" ];

          environment.HOME = "/tmp";

          serviceConfig = {
            User = "feltfomo";
            Group = "users";
            EnvironmentFile = config.sops.secrets."desktop-commander-mcp-token".path;
            ExecStart = "${pkgs.caddy}/bin/caddy run --config ${proxyConfig} --adapter caddyfile";
            Restart = "on-failure";
            RestartSec = "5s";

            CapabilityBoundingSet = "";
            IPAddressAllow = "localhost";
            IPAddressDeny = "any";
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
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
        };

        desktop-commander-mcp-funnel = {
          description = "Publish Desktop Commander MCP through Tailscale Funnel";
          after = [
            "desktop-commander-mcp-auth-proxy.service"
            "tailscaled.service"
          ];
          requires = [
            "desktop-commander-mcp-auth-proxy.service"
            "tailscaled.service"
          ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --set-path=/desktop-commander-mcp/mcp http://127.0.0.1:8087/mcp";
          };
        };
      };
    };
}
