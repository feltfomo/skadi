{
  config,
  lib,
  pkgs,
  ...
}:
let
  contract = import ./contract.nix { inherit lib; };
  furnish = import ./default.nix {
    inherit lib;
    resolve = throw "furnish runtime forced the user ownership resolver";
    resolveSystem = throw "furnish runtime forced the system ownership resolver";
  };
  cfg = config.lexicon.furnish;

  coordinator = pkgs.rustPlatform.buildRustPackage {
    pname = "furnish-coordinator";
    version = "0.1.0";
    src = ./coordinator;
    cargoLock.lockFile = ./coordinator/Cargo.lock;
  };

  nativeSymlinkExecutor = {
    inherit (contract.executors.nativeSymlink) identity protocolVersion;
    priority = 0;
    enabled = true;
    capabilities = [
      contract.capabilities.lifecycleBaseline
      contract.capabilities.symlink
    ];
    materialize = declaration: {
      retainedArtifactTarget = builtins.path {
        path = declaration.source.value;
        name = "furnish-${baseNameOf declaration.filesystemIdentity.destination}";
      };
      cleanupStrategy = contract.strategies.exactSymlinkTarget;
      selfHealStrategy = contract.strategies.exactSymlinkTarget;
    };
  };

  compiled = furnish.compile {
    inherit (cfg) declarations;
    executors = [ nativeSymlinkExecutor ];
    provider = furnish.core.offProvider;
  };

  manifestPath =
    if compiled.manifestData == [ ] then
      null
    else
      pkgs.writeText "furnish-desired-v${toString contract.schemaVersion}.json" compiled.manifestJson;

  lockName =
    lib.replaceStrings [ "/" ] [ "-" ]
      "${pkgs.stdenv.hostPlatform.system}/${config.networking.hostName}";

  destinationPaths = lib.unique (
    map (entry: entry.filesystemIdentity.destination) compiled.manifestData
  );
in
{
  options.lexicon.furnish = {
    declarations = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Furnish declarations selected for this host.";
    };
    manifestData = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      description = "Compiled furnish entries for runtime and regression inspection.";
    };
    manifestPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Closure-retained desired-state manifest consumed by the coordinator.";
    };
  };

  config = lib.mkMerge [
    {
      lexicon.furnish = {
        inherit (compiled) manifestData;
        inherit manifestPath;
      };
    }
    (lib.mkIf (manifestPath != null) {
      environment.systemPackages = [ coordinator ];

      # This is intentionally thin. The literal manifest interpolation makes the
      # manifest (and its context-retained targets) part of the active toplevel.
      system.activationScripts.furnish = {
        deps = [ "users" ];
        text = ''
          ${coordinator}/bin/furnish-coordinator reconcile \
            --manifest ${manifestPath} \
            --lock-name furnish-${lockName}.lock \
            --setpriv ${pkgs.util-linux}/bin/setpriv
        '';
      };

      # Activation runs before persisted destination mounts are guaranteed to be
      # visible during boot. Reconcile again after the generic mount dependencies
      # for every compiled destination, while retaining activation for switches.
      systemd.services.furnish = {
        description = "Reconcile furnish-managed filesystem destinations";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        unitConfig.RequiresMountsFor = destinationPaths;
        serviceConfig = {
          Type = "oneshot";
          # Run once on every boot, then remain active so switch-to-configuration
          # does not replay this boot-only reconcile within the same boot.
          RemainAfterExit = true;
        };
        script = ''
          ${coordinator}/bin/furnish-coordinator reconcile \
            --manifest ${manifestPath} \
            --lock-name furnish-${lockName}.lock \
            --setpriv ${pkgs.util-linux}/bin/setpriv
        '';
      };
    })
  ];
}
