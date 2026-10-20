{
  inputs,
  lib,
  pkgs,
}:
let
  mcp = import ../../../lib/mcp.nix { inherit lib; };
  proxy = mcp.mkProxyPackage {
    inherit pkgs;
    source = inputs.mcp-proxy;
  };
  projectRoot = "/home/feltfomo/Projects/fomo-client";
  minecraftSourceRoot = "/home/feltfomo/mc-src-vanilla";
  repositoryDirectories = [
    "/home/feltfomo/Projects/odyssey"
    projectRoot
    minecraftSourceRoot
  ];
  worktreeDirectories = [
    "/home/feltfomo/Projects/odyssey-fixes"
    "/home/feltfomo/Projects/odyssey-plans"
  ];
  allowedDirectories = repositoryDirectories ++ worktreeDirectories;
  readOnlyGitDirectories = map (directory: "-${directory}/.git") allowedDirectories;
  writableGitHookDirectories = map (directory: "-${directory}/.git/hooks") repositoryDirectories;
  inaccessiblePaths = [
    "-/run/secrets"
    "-/persist"
  ];
  # systemd stops the service cgroup; command output survives in this directory.
  runLogDirectory = "/var/lib/desktop-commander-mcp/runs";
  # mcp commands use bourne syntax that fish cannot parse.
  dcShell = pkgs.writeShellApplication {
    name = "dc-shell";
    runtimeInputs = [
      pkgs.bashInteractive
      pkgs.coreutils
    ];
    text = ''
      mkdir -p "${runLogDirectory}"
      log="${runLogDirectory}/$(date +%Y%m%dT%H%M%S)-$$.log"
      if [ "''${1:-}" = "-c" ]; then
        shift
        printf '# cwd %s\n# cmd %s\n' "$PWD" "$*" >"$log"
        bash -c "$*" 2>&1 | tee -a "$log"
      else
        printf '# cwd %s\n# argv %s\n' "$PWD" "$*" >"$log"
        bash "$@" 2>&1 | tee -a "$log"
      fi
    '';
  };
  desktopCommanderConfig = pkgs.writeText "desktop-commander-config.json" (
    builtins.toJSON {
      inherit allowedDirectories;
      abTest_McpUiPreviews = "notShowMCPUi";
      blockedCommands = [
        "nixos-rebuild"
        "grub-install"
        "nix-store"
        "systemctl"
        "diskpart"
        "firewall"
        "iptables"
        "poweroff"
        "shutdown"
        "adduser"
        "bcdedit"
        "nix-env"
        "takeown"
        "useradd"
        "usermod"
        "cipher"
        "format"
        "parted"
        "passwd"
        "reboot"
        "umount"
        "visudo"
        "fdisk"
        "mount"
        "netsh"
        "runas"
        "chsh"
        "halt"
        "init"
        "mkfs"
        "sudo"
        "net"
        "reg"
        "sfc"
        "dd"
        "sc"
        "su"
      ];
      defaultShell = "${dcShell}/bin/dc-shell";
      fileReadLineLimit = 1000;
      fileWriteLineLimit = 5000;
      pendingWelcomeOnboarding = false;
      telemetryEnabled = false;
      welcomeOnboardingEligible = false;
    }
  );
  backendUnits = [ "desktop-commander-mcp-server.service" ];
  ngrokDomain = "snooper-captive-reactor.ngrok-free.dev";
in
{
  inherit
    mcp
    proxy
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
}
