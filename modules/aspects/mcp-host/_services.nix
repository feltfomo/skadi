{
  inputs,
  pkgs,
  mcp,
  proxy,
  inaccessiblePaths,
  projectRoot,
  minecraftSourceRoot,
  allowedDirectories,
  readOnlyGitDirectories,
  writableGitHookDirectories,
  dcShell,
  desktopCommanderConfig,
  desktopCommander,
  minecraftModding,
  codebaseMemory,
  serena,
  gradleMcp,
  lldbMcp,
  serenaJdtlsRoot,
  serenaConfig,
  serenaProjectConfig,
}:
let
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
        SHELL = "${dcShell}/bin/dc-shell";
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
        # ps/pgrep/pkill were missing, so process inspection silently returned
        # nothing instead of reporting that the tool was absent.
        procps
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
      extraServiceConfig = {
        # the default (mixed) sigkills the whole cgroup on stop, so a rebuild
        # or a restart destroys every long job the agent has in flight. only
        # the proxy is the service; the work it spawned is allowed to finish
        # and keeps writing to its run log.
        KillMode = "process";
      };
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
in
backendServices
