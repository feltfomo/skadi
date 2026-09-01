{
  den.aspects.github-mcp.nixos =
    { pkgs, ... }:
    let
      proxyConfig = pkgs.writeText "github-mcp-proxy.caddyfile" ''
        {
          admin off
          auto_https off
        }

        :8083 {
          bind 127.0.0.1

          reverse_proxy http://127.0.0.1:8082 {
            header_up Host 127.0.0.1:8082
          }
        }
      '';
    in
    {
      environment.systemPackages = [ pkgs.github-mcp-server ];

      systemd.services = {
        github-mcp-server = {
          description = "GitHub MCP server";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            GITHUB_READ_ONLY = "1";
            GITHUB_TOOLSETS = "default";
          };

          serviceConfig = {
            ExecStart = "${pkgs.github-mcp-server}/bin/github-mcp-server http --listen-host 127.0.0.1 --base-url https://khion.tail4f0c8e.ts.net --base-path /github-mcp/mcp";
            Restart = "on-failure";
            RestartSec = "5s";

            DynamicUser = true;
            CapabilityBoundingSet = "";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
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

        github-mcp-proxy = {
          description = "GitHub MCP host-header proxy";
          after = [ "github-mcp-server.service" ];
          requires = [ "github-mcp-server.service" ];
          wantedBy = [ "multi-user.target" ];

          environment.HOME = "/tmp";

          serviceConfig = {
            ExecStart = "${pkgs.caddy}/bin/caddy run --config ${proxyConfig} --adapter caddyfile";
            Restart = "on-failure";
            RestartSec = "5s";

            DynamicUser = true;
            CapabilityBoundingSet = "";
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

        github-mcp-funnel = {
          description = "Publish GitHub MCP through Tailscale Funnel";
          after = [
            "github-mcp-proxy.service"
            "tailscaled.service"
          ];
          requires = [
            "github-mcp-proxy.service"
            "tailscaled.service"
          ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --set-path=/github-mcp/mcp http://127.0.0.1:8083";
            ExecStartPost = "${pkgs.tailscale}/bin/tailscale funnel --bg --set-path=/.well-known/oauth-protected-resource/github-mcp/mcp http://127.0.0.1:8083/.well-known/oauth-protected-resource/github-mcp/mcp";
          };
        };
      };
    };
}
