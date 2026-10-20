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
      nodejs_22
      gnugrep
      python3
      ripgrep
      gnused
      # ps/pgrep/pkill were missing, so process inspection silently returned
      # nothing instead of reporting that the tool was absent.
      procps
      which
      fish
      nix
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
      # mixed would kill running jobs when the proxy restarts during a rebuild.
      # stop only the proxy so its jobs can finish and keep writing their logs.
      KillMode = "process";
    };
  };
}
