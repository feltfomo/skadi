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
  allowedDirectories = [
    "/home/feltfomo/Projects/axiom-nix"
    "/home/feltfomo/Projects/lexicon"
    "/home/feltfomo/Projects/krisis"
    "/home/feltfomo/Projects/furnish-coordinator"
    "/etc/skadi"
    "/home/feltfomo/Projects/odyssey"
    projectRoot
    minecraftSourceRoot
  ];
  readOnlyGitDirectories = map (directory: "-${directory}/.git") allowedDirectories;
  writableGitHookDirectories = map (directory: "-${directory}/.git/hooks") allowedDirectories;
  inaccessiblePaths = [
    "-/persist"
    "-/run/secrets"
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
      defaultShell = "${dcShell}/bin/dc-shell";
      fileReadLineLimit = 1000;
      fileWriteLineLimit = 5000;
      pendingWelcomeOnboarding = false;
      telemetryEnabled = false;
      welcomeOnboardingEligible = false;
    }
  );
  backendUnits = [
    "desktop-commander-mcp-server.service"
    "minecraft-modding-mcp-server.service"
    "codebase-memory-mcp-server.service"
    "serena-mcp-server.service"
    "gradle-mcp-server.service"
    "mcp-nixos-mcp-server.service"
  ];
  ngrokDomain = "snooper-captive-reactor.ngrok-free.dev";
in
{
  inherit
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
}
