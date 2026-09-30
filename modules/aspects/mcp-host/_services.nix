{
  pkgs,
  mcp,
  proxy,
  inaccessiblePaths,
  allowedDirectories,
  readOnlyGitDirectories,
  writableGitHookDirectories,
  dcShell,
  desktopCommanderConfig,
  desktopCommander,
}:
{
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
}
