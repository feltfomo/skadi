{ inputs, ... }:
{
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
        mcp = import ../../lib/mcp.nix { inherit lib; };
        proxy = mcp.mkProxyPackage {
          inherit pkgs;
          source = inputs.mcp-proxy;
        };
        projectRoot = "/home/feltfomo/Projects/fomo-client";
        minecraftSourceRoot = "/home/feltfomo/mc-src";
        allowedDirectories = [
          "/home/feltfomo/Projects/axiom-nix"
          "/home/feltfomo/Projects/lexicon"
          "/home/feltfomo/Projects/krisis"
          "/home/feltfomo/Projects/furnish-coordinator"
          "/etc/skadi"
          "/home/feltfomo/Projects/rime"
          projectRoot
          minecraftSourceRoot
        ];
        readOnlyGitDirectories = map (directory: "-${directory}/.git") allowedDirectories;
        writableGitHookDirectories = map (directory: "-${directory}/.git/hooks") allowedDirectories;
        inaccessiblePaths = [
          "-/persist"
          "-/run/secrets"
        ];
        desktopCommanderConfig = pkgs.writeText "desktop-commander-config.json" (
          builtins.toJSON {
            inherit allowedDirectories;
            abTest_McpUiPreviews = "notShowMCPUi";
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
            fileWriteLineLimit = 5000;
            pendingWelcomeOnboarding = false;
            telemetryEnabled = false;
            welcomeOnboardingEligible = false;
          }
        );
        desktopCommander = pkgs.buildNpmPackage {
          pname = "desktop-commander";
          version = "0.2.47";
          src = inputs.desktop-commander;
          npmDeps = pkgs.importNpmLock { npmRoot = inputs.desktop-commander; };
          npmConfigHook = pkgs.importNpmLock.npmConfigHook;
          npmRebuildFlags = [ "--ignore-scripts" ];
          dontCheckForBrokenSymlinks = true;
          postConfigure = ''
            find -path "*@vscode/ripgrep" -type d \
              -execdir mkdir -p {}/bin \; \
              -execdir ln -sf ${pkgs.ripgrep}/bin/rg {}/bin/rg \;
          '';
        };
        minecraftSource = pkgs.fetchFromGitHub {
          owner = "adhi-jp";
          repo = "minecraft-modding-mcp";
          rev = "f9947bfcbc8a055d1d6d3de09ebaf62f3eb2e7b3";
          hash = "sha256-c/7DEKCX92thWBMH7GouIO0iS0P4yiKq7SMX3vSQB/4=";
        };
        minecraftModding = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "minecraft-modding-mcp";
          version = "7.0.0-rc.1";
          src = minecraftSource;
          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (finalAttrs) pname version src;
            pnpm = pkgs.pnpm_10;
            fetcherVersion = 3;
            hash = "sha256-mT05VPQh3TRzbHaEoN3H7+RHnIBwOqDLRwFHIsWn2uA=";
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
            cp -r dist node_modules package.json $out/lib/minecraft-modding-mcp/
            makeWrapper ${pkgs.nodejs_24}/bin/node $out/bin/minecraft-modding-mcp \
              --add-flags $out/lib/minecraft-modding-mcp/dist/cli.js
            runHook postInstall
          '';
        });
        codebaseMemorySource = pkgs.fetchFromGitHub {
          owner = "DeusData";
          repo = "codebase-memory-mcp";
          rev = "5802ccdd77c9913f8643092839c698bad10b2c4a";
          hash = "sha256-W7697fCzfjSIuEqQgJRkLE6VBhfwK/lHO8AiKB6hYAY=";
        };
        codebaseMemory = pkgs.stdenv.mkDerivation {
          pname = "codebase-memory-mcp";
          version = "0.10.8";
          src = codebaseMemorySource;
          nativeBuildInputs = [ pkgs.gnumake ];
          buildInputs = [ pkgs.zlib ];
          buildPhase = "make -j$NIX_BUILD_CORES -f Makefile.cbm cbm";
          installPhase = "install -Dm755 build/c/codebase-memory-mcp $out/bin/codebase-memory-mcp";
        };
        serena = inputs.serena.packages.${pkgs.stdenv.hostPlatform.system}.serena;
        # solidlsp passes --stdio, but fwcd's kotlin server rejects that flag.
        serenaKotlinLanguageServer = pkgs.writeShellApplication {
          name = "serena-kotlin-language-server";
          text = ''
            if [ "''${1-}" = "--stdio" ]; then
              shift
            fi
            exec ${pkgs.kotlin-language-server}/bin/kotlin-language-server "$@"
          '';
        };
        serenaJdtlsRoot = "/var/lib/serena-mcp/jdtls";
        serenaNixdConfig = pkgs.writeText "serena-nixd.json" (
          builtins.toJSON {
            nixpkgs.expr = "import <nixpkgs> { }";
            formatting.command = [ "${pkgs.nixfmt}/bin/nixfmt" ];
          }
        );
        serenaConfig = pkgs.writeText "serena-config.yml" ''
          language_backend: LSP
          web_dashboard: false
          web_dashboard_open_on_launch: false
          gui_log_window: false
          log_level: 30
          tool_timeout: 300
          base_modes:
            - no-memories
          default_modes:
            - planning
          project_serena_folder_location: "/var/lib/serena-mcp/projects/$projectFolderName/.serena"
          trusted_project_path_patterns:
            - ${projectRoot}
          projects:
            - ${projectRoot}
          ls_specific_settings:
            kotlin:
              ls_path: "${serenaKotlinLanguageServer}/bin/serena-kotlin-language-server"
            java:
              jdtls_path: "${serenaJdtlsRoot}"
              lombok_path: "${lib.getOutput "out" pkgs.lombok}/share/java/lombok.jar"
              java_home: "${pkgs.jdk21}"
              gradle_java_home: "${pkgs.jdk25}"
              gradle_user_home: "/var/lib/serena-mcp/gradle"
              gradle_wrapper_enabled: true
              runtimes:
                - name: "JavaSE-25"
                  path: "${pkgs.jdk25}"
                  default: true
            rust:
              ls_path: "${pkgs.rust-analyzer}/bin/rust-analyzer"
            cpp:
              ls_path: "${pkgs.clang-tools}/bin/clangd"
            nix:
              ls_path: "${pkgs.nixd}/bin/nixd"
              config_path: "${serenaNixdConfig}"
        '';
        serenaProjectConfig = pkgs.writeText "fomo-client-serena-project.yml" ''
          project_name: fomo-client
          languages:
            - kotlin
            - java
            - rust
            - cpp
            - nix
          language_backend: LSP
          read_only: true
          ignored_paths:
            - .devenv
            - .git
            - .gradle
            - .idea
            - .kotlin
            - .runtime
            - build
            - helios/target
            - logs
            - visibility-accelerator/target
          excluded_tools:
            - create_text_file
            - delete_lines
            - execute_shell_command
            - insert_after_symbol
            - insert_at_line
            - insert_before_symbol
            - replace_content
            - replace_lines
            - replace_symbol_body
            - write_memory
        '';
        gradleMcpJar = pkgs.fetchurl {
          url = "https://repo1.maven.org/maven2/dev/rnett/gradle-mcp/gradle-mcp/0.0.15/gradle-mcp-0.0.15.jar";
          hash = "sha256-UeoA/aONeVBFlUwfyqL520sESH/B7lWvb+Z3g4b4R3I=";
        };
        gradleMcp = pkgs.writeShellApplication {
          name = "gradle-mcp";
          runtimeInputs = [ pkgs.jdk25 ];
          text = ''
            exec java \
              -Duser.home="$HOME" \
              -Djava.io.tmpdir="$TMPDIR" \
              -jar ${gradleMcpJar} stdio "$@"
          '';
        };
        lldbMcp = pkgs.llvmPackages_latest.lldb;
        backendUnits = [
          "desktop-commander-mcp-server.service"
          "minecraft-modding-mcp-server.service"
          "codebase-memory-mcp-server.service"
          "serena-mcp-server.service"
          "gradle-mcp-server.service"
          "mcp-nixos-mcp-server.service"
        ];
        backendServices = {
          desktop-commander-mcp-server = mcp.mkStdioService {
            inherit proxy inaccessiblePaths;
            description = "Sandboxed Desktop Commander MCP server";
            port = 8086;
            command = [
              "${desktopCommander}/bin/desktop-commander"
              "--no-onboarding"
            ];
            workingDirectory = builtins.head allowedDirectories;
            stateDirectory = "desktop-commander-mcp";
            environment = {
              DESKTOP_COMMANDER_DISABLE_TELEMETRY = "1";
              HOME = "/var/lib/desktop-commander-mcp";
              SHELL = "${pkgs.fish}/bin/fish";
              TMPDIR = "/var/lib/desktop-commander-mcp";
            };
            path = with pkgs; [
              bashInteractive
              coreutils
              findutils
              fish
              gnugrep
              gnused
              nix
              nodejs_22
              python3
              ripgrep
              which
            ];
            readOnlyPaths = [
              "${desktopCommanderConfig}:/var/lib/desktop-commander-mcp/.claude-server-commander/config.json"
            ]
            ++ readOnlyGitDirectories;
            readWritePaths = allowedDirectories ++ writableGitHookDirectories;
            memoryHigh = "6G";
            memoryMax = "10G";
            tasksMax = 1024;
          };
          minecraft-modding-mcp-server = mcp.mkStdioService {
            inherit proxy inaccessiblePaths;
            description = "Minecraft modding MCP server";
            port = 8090;
            command = [ "${minecraftModding}/bin/minecraft-modding-mcp" ];
            workingDirectory = projectRoot;
            stateDirectory = "minecraft-modding-mcp";
            environment = {
              HOME = "/var/lib/minecraft-modding-mcp";
              MCP_CACHE_DIR = "/var/lib/minecraft-modding-mcp/cache";
              MCP_VALIDATE_PROJECT_TIMEOUT_MS = "300000";
            };
            path = [
              pkgs.jdk25
              pkgs.unzip
            ];
            readOnlyPaths = [
              projectRoot
              minecraftSourceRoot
            ];
          };
          codebase-memory-mcp-server = mcp.mkStdioService {
            inherit proxy inaccessiblePaths;
            description = "Codebase Memory MCP server";
            port = 8091;
            command = [ "${codebaseMemory}/bin/codebase-memory-mcp" ];
            workingDirectory = projectRoot;
            stateDirectory = "codebase-memory-mcp";
            environment = {
              HOME = "/var/lib/codebase-memory-mcp";
              CBM_CACHE_DIR = "/var/lib/codebase-memory-mcp/cache";
            };
            path = [ pkgs.git ];
            readOnlyPaths = [ projectRoot ];
            networkAccess = false;
            memoryHigh = "4G";
            memoryMax = "8G";
          };
          serena-mcp-server = mcp.mkStdioService {
            inherit proxy inaccessiblePaths;
            description = "Read-only Serena semantic code MCP server";
            port = 8092;
            command = [
              "${serena}/bin/serena"
              "start-mcp-server"
              "--project"
              projectRoot
              "--context"
              "ide"
              "--mode"
              "planning"
              "--enable-web-dashboard"
              "false"
              "--open-web-dashboard"
              "false"
              "--enable-gui-log-window"
              "false"
              "--log-level"
              "WARNING"
            ];
            workingDirectory = projectRoot;
            stateDirectory = "serena-mcp";
            environment = {
              HOME = "/var/lib/serena-mcp";
              TMPDIR = "/var/lib/serena-mcp/tmp";
              JAVA_HOME = "${pkgs.jdk21}";
              CARGO_HOME = "/var/lib/serena-mcp/cargo";
              GRADLE_USER_HOME = "/var/lib/serena-mcp/gradle";
              NIX_PATH = "nixpkgs=${inputs.nixpkgs}";
            };
            path = [
              pkgs.cargo
              pkgs.clang-tools
              pkgs.gradle
              pkgs.jdk21
              pkgs.jdk25
              pkgs.jdt-language-server
              pkgs.kotlin-language-server
              pkgs.nixd
              pkgs.rust-analyzer
              pkgs.rustc
            ];
            readOnlyPaths = [ projectRoot ];
            networkAccess = false;
            memoryHigh = "4G";
            memoryMax = "8G";
            tasksMax = 1024;
            extraServiceConfig.ExecStartPre = [
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users /var/lib/serena-mcp/.serena"
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users /var/lib/serena-mcp/.serena/memories/global"
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users /var/lib/serena-mcp/tmp"
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users /var/lib/serena-mcp/cargo"
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users /var/lib/serena-mcp/gradle"
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users ${serenaJdtlsRoot}/config_linux"
              "+${pkgs.coreutils}/bin/ln -sfn ${pkgs.jdt-language-server}/share/java/jdtls/plugins ${serenaJdtlsRoot}/plugins"
              "+${pkgs.coreutils}/bin/install -m 0600 -o feltfomo -g users ${pkgs.jdt-language-server}/share/java/jdtls/config_linux/config.ini ${serenaJdtlsRoot}/config_linux/config.ini"
              "+${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/chmod -R u+rwX /var/lib/serena-mcp/.serena/language_servers 2>/dev/null || true'"
              "+${pkgs.coreutils}/bin/install -d -m 0700 -o feltfomo -g users /var/lib/serena-mcp/projects/fomo-client/.serena"
              "+${pkgs.coreutils}/bin/install -m 0600 -o feltfomo -g users ${serenaConfig} /var/lib/serena-mcp/.serena/serena_config.yml"
              "+${pkgs.coreutils}/bin/install -m 0600 -o feltfomo -g users ${serenaProjectConfig} /var/lib/serena-mcp/projects/fomo-client/.serena/project.yml"
            ];
          };
          gradle-mcp-server = mcp.mkStdioService {
            inherit proxy inaccessiblePaths;
            description = "Pinned Gradle project MCP server";
            port = 8093;
            command = [ "${gradleMcp}/bin/gradle-mcp" ];
            workingDirectory = projectRoot;
            stateDirectory = "gradle-mcp";
            environment = {
              HOME = "/var/lib/gradle-mcp";
              TMPDIR = "/var/lib/gradle-mcp/tmp";
              GRADLE_MCP_LOG_DIR = "/var/lib/gradle-mcp/logs";
              GRADLE_MCP_PROJECT_ROOT = projectRoot;
              GRADLE_USER_HOME = "${projectRoot}/.gradle";
            };
            path = [
              pkgs.bashInteractive
              pkgs.coreutils
              pkgs.git
              pkgs.jdk25
            ];
            readOnlyPaths = [ "-${projectRoot}/.git" ];
            readWritePaths = [ projectRoot ];
            memoryHigh = "6G";
            memoryMax = "10G";
            tasksMax = 1024;
          };
          lldb-mcp-server =
            (mcp.mkStdioService {
              inherit proxy inaccessiblePaths;
              description = "Official LLVM LLDB MCP server";
              port = 8094;
              command = [ "${lldbMcp}/bin/lldb-mcp" ];
              workingDirectory = projectRoot;
              stateDirectory = "lldb-mcp";
              environment = {
                HOME = "/var/lib/lldb-mcp";
                TMPDIR = "/var/lib/lldb-mcp/tmp";
              };
              readOnlyPaths = [ projectRoot ];
              networkAccess = false;
              memoryHigh = "4G";
              memoryMax = "8G";
              tasksMax = 1024;
            })
            // {
              # lldb-mcp is not compatible with the stdio proxy yet.
              # keep the unit available for manual debugging without autostart.
              wantedBy = [ ];
            };
          mcp-nixos-mcp-server = mcp.mkStdioService {
            inherit proxy inaccessiblePaths;
            description = "NixOS documentation and package MCP server";
            port = 8095;
            command = [ "${pkgs.mcp-nixos}/bin/mcp-nixos" ];
            workingDirectory = "/var/lib/mcp-nixos-mcp";
            stateDirectory = "mcp-nixos-mcp";
            environment = {
              HOME = "/var/lib/mcp-nixos-mcp";
              TMPDIR = "/var/lib/mcp-nixos-mcp";
            };
            path = [ pkgs.nix ];
            readOnlyPaths = [ "/nix/store" ];
            memoryHigh = "1G";
            memoryMax = "2G";
            tasksMax = 256;
          };
        };
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
        authorizedContext7Proxy = ''
          @context7Authorized header Authorization "Bearer {$DESKTOP_COMMANDER_MCP_TOKEN}"
          handle @context7Authorized {
            reverse_proxy https://mcp.context7.com {
              header_up Host mcp.context7.com
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
              ${authorizedContext7Proxy}
            }
            respond "Not found" 404
          }
        '';
        ngrokDomain = "snooper-captive-reactor.ngrok-free.dev";
        tunnelControl = pkgs.writeShellApplication {
          name = "desktop-commander-tunnel";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.systemd
          ];
          text = ''
            set -eu
            provider="''${1:-}"
            action="''${2:-status}"
            case "$provider" in
              ngrok) unit=desktop-commander-mcp-ngrok.service ;;
              cloudflare|cloudflare-quick) unit=desktop-commander-mcp-cloudflare-quick.service ;;
              *)
                echo "usage: desktop-commander-tunnel ngrok|cloudflare|cloudflare-quick status|logs|start|stop|restart|url" >&2
                exit 2
                ;;
            esac
            case "$action" in
              status) systemctl status "$unit" --no-pager ;;
              logs) journalctl -u "$unit" -f ;;
              start|stop|restart) /run/wrappers/bin/sudo systemctl "$action" "$unit" ;;
              url)
                if [ "$provider" = ngrok ]; then
                  echo "https://${ngrokDomain}/mcp"
                  exit 0
                fi
                url="$(journalctl -u "$unit" -n 200 --no-pager | grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -n 1 || true)"
                [ -n "$url" ] || { echo "no quick tunnel url found" >&2; exit 1; }
                echo "$url/mcp"
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
            pkgs.systemd
          ];
          text = ''
                    set -eu
                    action="''${1:-status}"
                    backends=(
                      ${lib.concatStringsSep "\n              " backendUnits}
                    )
                    case "$action" in
                      status) systemctl status mcp-host-gateway.service desktop-commander-mcp-ngrok.service "''${backends[@]}" --no-pager ;;
                      recover)
                        /run/wrappers/bin/sudo systemctl restart mcp-host-gateway.service
                        /run/wrappers/bin/sudo systemctl restart desktop-commander-mcp-ngrok.service
                        ;;
                      reset)
                        /run/wrappers/bin/sudo systemctl stop desktop-commander-mcp-ngrok.service
                        /run/wrappers/bin/sudo systemctl restart "''${backends[@]}"
                        /run/wrappers/bin/sudo systemctl restart mcp-host-gateway.service
                        /run/wrappers/bin/sudo systemctl start desktop-commander-mcp-ngrok.service
                        ;;
                      test)
                        curl --fail --silent http://127.0.0.1:8087/health >/dev/null
                        for port in 8086 8090 8091 8092 8093 8095; do curl --fail --silent "http://127.0.0.1:$port/ping" >/dev/null; done
                        status="$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8087/mcp)"
                        [ "$status" = 401 ]
                        echo "mcp host is healthy"
                        ;;
                      urls)
                        echo "https://${ngrokDomain}/mcp"
                        echo "https://${ngrokDomain}/minecraft/mcp"
                        echo "https://${ngrokDomain}/codebase-memory/mcp"
                        echo "https://${ngrokDomain}/serena/mcp"
                        echo "https://${ngrokDomain}/gradle/mcp"
            echo "https:""//${ngrokDomain}/nixos/mcp"
            echo "https:""//${ngrokDomain}/context7/mcp"
                        ;;
                      *) echo "usage: mcp-host status|recover|reset|test|urls" >&2; exit 2 ;;
                    esac
          '';
        };
        tunnelHardening = mcp.hardening // {
          DynamicUser = true;
          Restart = "always";
          RestartSec = "5s";
          TimeoutStopSec = "10s";
          ProtectHome = true;
        };
        ngrokRunner = pkgs.writeShellScript "run-mcp-host-ngrok" ''
          export NGROK_AUTHTOKEN="$(cat "$CREDENTIALS_DIRECTORY/authtoken")"
          exec ${pkgs.ngrok}/bin/ngrok http 8087 --url "${ngrokDomain}" --host-header=rewrite
        '';
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
            wantedBy = [ "multi-user.target" ];
            serviceConfig = tunnelHardening // {
              LoadCredential = "authtoken:${config.sops.secrets."desktop-commander-ngrok-authtoken".path}";
              ExecStart = ngrokRunner;
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
