{
  pkgs,
  mcp,
  ngrokDomain,
}:
let
  gatewayConfig = pkgs.writeText "mcp-host.caddyfile" ''
    {
      admin off
      auto_https off
      persist_config off
    }

    :8087 {
      bind 127.0.0.1
      log {
        output stderr
        format console
      }
      handle /health {
        respond "ok" 200
      }
      handle /mcp {
        @desktopAuthorized header Authorization "Bearer {$DESKTOP_COMMANDER_MCP_TOKEN}"
        handle @desktopAuthorized {
          reverse_proxy http://127.0.0.1:8086 {
            header_up Host 127.0.0.1:8086
            header_up -Authorization
            flush_interval -1
            transport http {
              versions 1.1
            }
          }
        }
        respond "Unauthorized" 401
      }
      respond "Not found" 404
    }
  '';
  tunnelHardening = mcp.hardening // {
    DynamicUser = true;
    Restart = "always";
    RestartSec = "5s";
    TimeoutStopSec = "10s";
    ProtectHome = true;
  };
  ngrokRunner = pkgs.writeShellScript "run-mcp-host-ngrok" ''
    export NGROK_AUTHTOKEN="$(cat "$CREDENTIALS_DIRECTORY/authtoken")"
    exec ${pkgs.ngrok}/bin/ngrok http 8087 --url "${ngrokDomain}"
  '';
  # --bg registers the mapping with tailscaled and exits, so use a oneshot.
  # DynamicUser would block access to /var/run/tailscale/tailscaled.sock.
  funnelStart = pkgs.writeShellScript "start-mcp-host-funnel" ''
    exec ${pkgs.tailscale}/bin/tailscale funnel --yes --bg --https=443 http://127.0.0.1:8087
  '';
  funnelStop = pkgs.writeShellScript "stop-mcp-host-funnel" ''
    exec ${pkgs.tailscale}/bin/tailscale funnel --yes --https=443 off
  '';
in
{
  inherit
    gatewayConfig
    tunnelHardening
    ngrokRunner
    funnelStart
    funnelStop
    ;
}
