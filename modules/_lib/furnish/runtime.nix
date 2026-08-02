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

  # generated file sources are build-time inputs to retained artifacts. keeping
  # them in the system closure makes fresh evaluation substitutable.
  generatedSources = builtins.filter lib.isDerivation (
    map (declaration: declaration.source.value) cfg.declarations
  );

  coordinator = import ./coordinator.nix { inherit pkgs; };

  nativeExecutor =
    {
      executorContract,
      representation,
      strategy,
    }:
    {
      inherit (executorContract) identity protocolVersion;
      priority = 0;
      enabled = true;
      capabilities = [
        contract.capabilities.lifecycleBaseline
        representation
      ];
      materialize = declaration: {
        retainedArtifactTarget = builtins.path {
          path = declaration.source.value;
          name = "furnish-${baseNameOf declaration.filesystemIdentity.destination}";
        };
        cleanupStrategy = strategy;
        selfHealStrategy = strategy;
      };
    };

  nativeSymlinkExecutor = nativeExecutor {
    executorContract = contract.executors.nativeSymlink;
    representation = contract.capabilities.symlink;
    strategy = contract.strategies.exactSymlinkTarget;
  };

  # writable changes the destination strategy while retaining the same artifact shape
  nativeWritableExecutor = nativeExecutor {
    executorContract = contract.executors.nativeWritable;
    representation = contract.capabilities.writable;
    strategy = contract.strategies.exactSourceContent;
  };

  compiled = furnish.compile {
    inherit (cfg) declarations;
    executors = [
      nativeSymlinkExecutor
      nativeWritableExecutor
    ];
    provider = furnish.core.offProvider;
  };

  # an enabled host always has a manifest, empty entry set included. the empty
  # reconciliation is what retires entries that are no longer declared, so it
  # needs something to reconcile against. disabled means inert, not empty.
  manifestPath =
    if cfg.enable then
      pkgs.writeText "furnish-desired-v${toString contract.schemaVersion}.json" compiled.manifestJson
    else
      null;

  lockName =
    lib.replaceStrings [ "/" ] [ "-" ]
      "${pkgs.stdenv.hostPlatform.system}/${config.networking.hostName}";

  destinationPaths = lib.unique (
    map (entry: entry.filesystemIdentity.destination) compiled.manifestData
  );

  ledgerPath = "${cfg.state.path}/${contract.ledger.fileName}";

  reconcileCommand = ''
    ${coordinator}/bin/furnish-coordinator reconcile \
      --manifest ${manifestPath} \
      --lock-name furnish-${lockName}.lock \
      --state-dir ${cfg.state.path} \
      --setpriv ${pkgs.util-linux}/bin/setpriv
  '';

  # nixos marks the initrd invocation before it enters the target root. every
  # other activation remains a reconcile, including an invocation with no mark.
  activationCommand = ''
    if [ "''${IN_NIXOS_SYSTEMD_STAGE1:-}" = true ]; then
      printf '%s\n' 'furnish activation boot path defers reconciliation to furnish.service'
    else
      ${reconcileCommand}
    fi
  '';
in
{
  options.lexicon.furnish = {
    enable = lib.mkEnableOption "furnish-managed filesystem reconciliation";
    state = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/furnish";
        description = "Directory holding the applied-state ledger.";
      };
      durability = lib.mkOption {
        type = lib.types.enum [
          "durable"
          "ephemeral"
        ];
        default = "ephemeral";
        # furnish cannot make its own state survive a root wipe; only the host
        # that owns the filesystem layout can. declaring durable is a claim the
        # consumer must prove, not a switch that arranges anything here.
        description = "Whether state.path is claimed to survive a root wipe.";
      };
      requiresMountsFor = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional mounts the reconcile unit must wait for, typically the filesystem carrying state.path.";
      };
    };
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
    ledgerPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Applied-state ledger the coordinator writes beneath state.path.";
    };
  };

  config = lib.mkMerge [
    {
      lexicon.furnish = {
        inherit (compiled) manifestData;
        inherit manifestPath ledgerPath;
      };
    }
    (lib.mkIf cfg.enable {
      system.extraDependencies = generatedSources;
      environment.systemPackages = [ coordinator ];

      # this is intentionally thin. the literal manifest interpolation makes the
      # manifest (and its context-retained targets) part of the active toplevel.
      system.activationScripts.furnish = {
        deps = [ "users" ];
        text = activationCommand;
      };

      # activation runs before persisted destination mounts are guaranteed to be
      # visible during boot. reconcile again after the generic mount dependencies
      # for every compiled destination, while retaining activation for switches.
      systemd.services.furnish = {
        description = "Reconcile furnish-managed filesystem destinations";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        # the ledger's filesystem is as load-bearing as the destinations. a
        # reconcile that cannot read applied state cannot prove ownership, and an
        # unproven destination is refused rather than repaired.
        unitConfig.RequiresMountsFor = lib.unique (destinationPaths ++ cfg.state.requiresMountsFor);
        serviceConfig = {
          Type = "oneshot";
          # run once on every boot, then remain active so switch-to-configuration
          # does not replay this boot-only reconcile within the same boot.
          RemainAfterExit = true;
        };
        script = reconcileCommand;
      };
    })
  ];
}
