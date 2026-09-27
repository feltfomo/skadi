{ inputs, ... }:
{
  flake-file.inputs = {
    desktop-commander = {
      url = "github:wonderwhy-er/DesktopCommanderMCP/e7dd3ab91237a4a4e2c00ad475e85c5f9f163ce9";
      flake = false;
    };
    mcp-proxy = {
      # each mcp session receives its own stdio child through the http bridge.
      url = "github:punkpeye/mcp-proxy/88ebe4aa6115d39bd27832c60a112cca277e8405";
      flake = false;
    };
    serena.url = "github:oraios/serena/801a388c2b7a6a8998f313291678b1609664e794";
  };

  den.aspects.desktop-commander-mcp = {
    persistence.directories = [
      "/var/lib/desktop-commander-mcp"
      "/var/lib/minecraft-modding-mcp"
      "/var/lib/codebase-memory-mcp"
      "/var/lib/serena-mcp"
      "/var/lib/gradle-mcp"
      "/var/lib/lldb-mcp"
      "/var/lib/mcp-nixos-mcp"
    ];

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        shared = import ./_shared.nix { inherit inputs lib pkgs; };
        inherit (shared)
          mcp
          proxy
          projectRoot
          minecraftSourceRoot
          allowedDirectories
          readOnlyGitDirectories
          writableGitHookDirectories
          inaccessiblePaths
          dcShell
          runLogDirectory
          desktopCommanderConfig
          backendUnits
          ngrokDomain
          ;
        packages = import ./_packages.nix { inherit inputs pkgs; };
        inherit (packages)
          desktopCommander
          minecraftModding
          codebaseMemory
          serena
          gradleMcp
          lldbMcp
          ;
        serenaFiles = import ./_serena.nix { inherit lib pkgs projectRoot; };
        inherit (serenaFiles) serenaJdtlsRoot serenaConfig serenaProjectConfig;
        backendServices = import ./_services.nix {
          inherit
            inputs
            pkgs
            mcp
            proxy
            inaccessiblePaths
            projectRoot
            minecraftSourceRoot
            allowedDirectories
            readOnlyGitDirectories
            writableGitHookDirectories
            dcShell
            desktopCommanderConfig
            desktopCommander
            minecraftModding
            codebaseMemory
            serena
            gradleMcp
            lldbMcp
            serenaJdtlsRoot
            serenaConfig
            serenaProjectConfig
            ;
        };
        gateway = import ./_gateway.nix { inherit pkgs mcp ngrokDomain; };
        inherit (gateway)
          gatewayConfig
          tunnelHardening
          ngrokRunner
          funnelStart
          funnelStop
          ;
        cli = import ./_cli.nix {
          inherit
            lib
            pkgs
            backendUnits
            ngrokDomain
            ;
        };
        inherit (cli) tunnelControl mcpHostControl;
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
        sops.secrets."desktop-commander-ngrok-authtoken" = { };
        skadi.provision.secrets.desktop-commander-ngrok-authtoken = {
          method = "paste";
          prompt = "ngrok authtoken";
        };
        environment.systemPackages = [
          desktopCommander
          minecraftModding
          codebaseMemory
          pkgs.mcp-nixos
          serena
          gradleMcp
          lldbMcp
          tunnelControl
          mcpHostControl
        ];
        systemd.tmpfiles.rules = [
          "d /var/lib/desktop-commander-mcp 0700 feltfomo users - -"
          "d /var/lib/desktop-commander-mcp/.claude-server-commander 0700 feltfomo users - -"
          "f /var/lib/desktop-commander-mcp/.claude-server-commander/config.json 0600 feltfomo users - -"
          "d ${runLogDirectory} 0700 feltfomo users 14d -"
          "d /var/lib/minecraft-modding-mcp 0700 feltfomo users - -"
          "d /var/lib/minecraft-modding-mcp/cache 0700 feltfomo users - -"
          "d /var/lib/codebase-memory-mcp 0700 feltfomo users - -"
          "d /var/lib/codebase-memory-mcp/cache 0700 feltfomo users - -"
          "d /var/lib/serena-mcp 0700 feltfomo users - -"
          "d /var/lib/serena-mcp/.serena 0700 feltfomo users - -"
          "f /var/lib/serena-mcp/.serena/serena_config.yml 0600 feltfomo users - -"
          "d /var/lib/serena-mcp/projects 0700 feltfomo users - -"
          "d /var/lib/serena-mcp/projects/fomo-client 0700 feltfomo users - -"
          "d /var/lib/serena-mcp/projects/fomo-client/.serena 0700 feltfomo users - -"
          "f /var/lib/serena-mcp/projects/fomo-client/.serena/project.yml 0600 feltfomo users - -"
          "d /var/lib/serena-mcp/tmp 0700 feltfomo users - -"
          "d /var/lib/gradle-mcp 0700 feltfomo users - -"
          "d /var/lib/gradle-mcp/logs 0700 feltfomo users - -"
          "d /var/lib/gradle-mcp/tmp 0700 feltfomo users - -"
          "d /var/lib/lldb-mcp 0700 feltfomo users - -"
          "d /var/lib/lldb-mcp/.lldb 0700 feltfomo users - -"
          "d /var/lib/lldb-mcp/tmp 0700 feltfomo users - -"
          "d /var/lib/mcp-nixos-mcp 0700 feltfomo users - -"
        ];
        systemd.services = backendServices // {
          mcp-host-gateway = {
            description = "Bearer-authenticated MCP gateway";
            after = backendUnits;
            wants = backendUnits;
            wantedBy = [ "multi-user.target" ];
            environment.HOME = "/tmp";
            serviceConfig = mcp.hardening // {
              User = "feltfomo";
              Group = "users";
              EnvironmentFile = config.sops.secrets."desktop-commander-mcp-token".path;
              ExecStart = "${pkgs.caddy}/bin/caddy run --config ${gatewayConfig} --adapter caddyfile";
              Restart = "always";
              RestartSec = "2s";
              ProtectHome = true;
            };
          };
          desktop-commander-mcp-ngrok = {
            description = "Publish the MCP gateway through ngrok";
            after = [
              "mcp-host-gateway.service"
              "network-online.target"
            ];
            requires = [ "mcp-host-gateway.service" ];
            wants = [ "network-online.target" ];
            # tailscale funnel is the default publisher now. the ngrok unit and
            # its authtoken stay provisioned so this is a one-command fallback:
            #   desktop-commander-tunnel ngrok start
            wantedBy = [ ];
            serviceConfig = tunnelHardening // {
              LoadCredential = "authtoken:${config.sops.secrets."desktop-commander-ngrok-authtoken".path}";
              ExecStart = ngrokRunner;
            };
          };
          desktop-commander-mcp-tailscale = {
            description = "Publish the MCP gateway through Tailscale Funnel";
            after = [
              "mcp-host-gateway.service"
              "tailscaled.service"
              "network-online.target"
            ];
            requires = [
              "mcp-host-gateway.service"
              "tailscaled.service"
            ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              # the mapping lives in tailscaled's own state, so this only has to
              # register it once and stay latched.
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = funnelStart;
              ExecStop = funnelStop;
              # a node that is not logged in yet fails here; retry instead of
              # leaving the gateway unpublished until the next boot.
              Restart = "on-failure";
              RestartSec = "10s";
            };
          };
          desktop-commander-mcp-cloudflare-quick = {
            description = "Publish the MCP gateway through a temporary Cloudflare tunnel";
            after = [
              "mcp-host-gateway.service"
              "network-online.target"
            ];
            requires = [ "mcp-host-gateway.service" ];
            wants = [ "network-online.target" ];
            serviceConfig = tunnelHardening // {
              ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:8087 --http-host-header 127.0.0.1:8087";
              Restart = "on-failure";
            };
          };
        };
      };
  };
}
