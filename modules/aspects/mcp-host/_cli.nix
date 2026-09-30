{
  lib,
  pkgs,
  backendUnits,
  ngrokDomain,
}:
let
  tunnelUnits = {
    tailscale = "desktop-commander-mcp-tailscale.service";
    ngrok = "desktop-commander-mcp-ngrok.service";
    cloudflare = "desktop-commander-mcp-cloudflare-quick.service";
  };
  # the funnel hostname is tailnet state rather than configuration, so resolve
  # it at runtime and fall back to the ngrok domain when no node is up. this
  # keeps the tailnet name out of the store.
  resolveBase = ''
    dns="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' || true)"
    dns="''${dns%.}"
    if [ -n "$dns" ]; then
      base="https://$dns"
    else
      base="https://${ngrokDomain}"
    fi
  '';
  tunnelControl = pkgs.writeShellApplication {
    name = "desktop-commander-tunnel";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.systemd
      pkgs.tailscale
    ];
    text = ''
      provider="''${1:-}"
      action="''${2:-status}"
      case "$provider" in
        tailscale|funnel) unit=${tunnelUnits.tailscale} ;;
        ngrok) unit=${tunnelUnits.ngrok} ;;
        cloudflare|cloudflare-quick) unit=${tunnelUnits.cloudflare} ;;
        *)
          echo "usage: desktop-commander-tunnel tailscale|ngrok|cloudflare status|logs|start|stop|restart|url" >&2
          exit 2
          ;;
      esac
      case "$action" in
        status) systemctl status "$unit" --no-pager ;;
        logs) journalctl -u "$unit" -f ;;
        start|stop|restart) /run/wrappers/bin/sudo systemctl "$action" "$unit" ;;
        url)
          case "$provider" in
            tailscale|funnel)
              dns="$(tailscale status --json | jq -r '.Self.DNSName // empty')"
              dns="''${dns%.}"
              [ -n "$dns" ] || { echo "tailscale node has no dns name; run: sudo tailscale up" >&2; exit 1; }
              echo "https://$dns/mcp"
              ;;
            ngrok) echo "https://${ngrokDomain}/mcp" ;;
            *)
              url="$(journalctl -u "$unit" -n 200 --no-pager | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1 || true)"
              [ -n "$url" ] || { echo "no quick tunnel url found" >&2; exit 1; }
              echo "$url/mcp"
              ;;
          esac
          ;;
        *) echo "unknown action: $action" >&2; exit 2 ;;
      esac
    '';
  };
  mcpHostControl = pkgs.writeShellApplication {
    name = "mcp-host";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.systemd
      pkgs.tailscale
    ];
    text = ''
      action="''${1:-status}"
      backends=(
        ${lib.concatStringsSep "\n        " backendUnits}
      )
      # the funnel is the default publisher; ngrok and cloudflare stay
      # installed and are driven through desktop-commander-tunnel.
      tunnel="${tunnelUnits.tailscale}"
      case "$action" in
        status) systemctl status mcp-host-gateway.service "$tunnel" "''${backends[@]}" --no-pager ;;
        recover)
          /run/wrappers/bin/sudo systemctl restart mcp-host-gateway.service
          /run/wrappers/bin/sudo systemctl restart "$tunnel"
          ;;
        reset)
          /run/wrappers/bin/sudo systemctl stop "$tunnel"
          /run/wrappers/bin/sudo systemctl restart "''${backends[@]}"
          /run/wrappers/bin/sudo systemctl restart mcp-host-gateway.service
          /run/wrappers/bin/sudo systemctl start "$tunnel"
          ;;
        test)
          curl --fail --silent http://127.0.0.1:8087/health >/dev/null
          curl --fail --silent http://127.0.0.1:8086/ping >/dev/null
          status="$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8087/mcp)"
          [ "$status" = 401 ]
          echo "mcp host is healthy"
          ;;
        urls)
          ${resolveBase}
          echo "$base/mcp"
          ;;
        *) echo "usage: mcp-host status|recover|reset|test|urls" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  inherit tunnelControl mcpHostControl;
}
