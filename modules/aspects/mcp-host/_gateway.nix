{
  pkgs,
  mcp,
  ngrokDomain,
}:
let
  authorizedProxy = matcher: port: ''
    @${matcher} header Authorization "Bearer {$DESKTOP_COMMANDER_MCP_TOKEN}"
    handle @${matcher} {
      reverse_proxy http://127.0.0.1:${toString port} {
        header_up Host 127.0.0.1:${toString port}
        flush_interval -1
        transport http {
          versions 1.1
        }
      }
    }
    respond "Unauthorized" 401
  '';
  # remote upstreams are authenticated at the gateway, then the bearer token is
  # stripped so it never leaves the machine.
  authorizedRemoteProxy = matcher: upstreamHost: ''
    @${matcher} header Authorization "Bearer {$DESKTOP_COMMANDER_MCP_TOKEN}"
    handle @${matcher} {
      reverse_proxy https://${upstreamHost} {
        header_up Host ${upstreamHost}
        header_up -Authorization
        flush_interval -1
      }
    }
    respond "Unauthorized" 401
  '';
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
      handle /mcp* {
        ${authorizedProxy "desktopAuthorized" 8086}
      }
      handle_path /minecraft/* {
        ${authorizedProxy "minecraftAuthorized" 8090}
      }
      handle_path /codebase-memory/* {
        ${authorizedProxy "codebaseMemoryAuthorized" 8091}
      }
      handle_path /serena/* {
        ${authorizedProxy "serenaAuthorized" 8092}
      }
      handle_path /gradle/* {
        ${authorizedProxy "gradleAuthorized" 8093}
      }
      handle_path /lldb/* {
        ${authorizedProxy "lldbAuthorized" 8094}
      }
      handle_path /nixos/* {
        ${authorizedProxy "nixosAuthorized" 8095}
      }
      handle_path /context7/* {
        ${authorizedRemoteProxy "context7Authorized" "mcp.context7.com"}
      }
      handle_path /kleisli/* {
        ${authorizedRemoteProxy "kleisliAuthorized" "docs.kleisli.io"}
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
  # funnel only proxies to http://127.0.0.1, which is exactly what the gateway
  # already binds, and only listens on 443, 8443, or 10000. --bg registers the
  # mapping with tailscaled and exits, so this is a oneshot rather than a
  # long-running child like the ngrok and cloudflare runners.
  #
  # this cannot use tunnelHardening: DynamicUser would deny access to
  # /var/run/tailscale/tailscaled.sock, which the cli needs to reconfigure the
  # daemon.
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
