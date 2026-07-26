_:
let
  schemaVersion = 1;
  diagnosticSchemaVersion = 1;

  capabilities = {
    symlink = "symlink";
    writable = "writable";
    lifecycleBaseline = "lifecycle-baseline";
  };

  strategies = {
    exactSymlinkTarget = "exact-symlink-target";
    exactSourceContent = "exact-source-content";
  };

  # The applied-state ledger is a separate document with its own version. The
  # manifest says what was asked for and changes when the desired shape changes;
  # the ledger says what this machine actually did and changes when the evidence
  # we keep changes. Versioning them together would force a manifest migration
  # every time the evidence grows a field.
  ledger = {
    schemaVersion = 2;
    fileName = "applied-state.json";
    # Written once, immediately before the first v2 write, so a downgrade has a
    # readable copy of the exact state the migration consumed.
    rollbackFileName = "applied-state.v1.json";
  };

  executors.nativeSymlink = {
    identity = "furnish/native-symlink";
    protocolVersion = 1;
    representation = capabilities.symlink;
  };

  executors.nativeWritable = {
    identity = "furnish/native-writable";
    protocolVersion = 1;
    representation = capabilities.writable;
  };

  runtimeDiagnostics = {
    schemaVersion = diagnosticSchemaVersion;
    codes = {
      invalidManifest = "runtime/invalid-manifest";
      unsupportedExecutor = "runtime/unsupported-executor";
      invalidDestination = "runtime/invalid-destination";
      parentTraversal = "runtime/parent-traversal";
      conflictingDestination = "runtime/conflicting-destination";
      executorFailed = "runtime/executor-failed";
      stagingVerification = "runtime/staging-verification";
      publishRace = "runtime/publish-race";
      finalVerification = "runtime/final-verification";
      ledgerUnreadable = "runtime/ledger-unreadable";
      ledgerInvalid = "runtime/ledger-invalid";
      ledgerWriteFailed = "runtime/ledger-write-failed";
      repairVerification = "runtime/repair-verification";
      unresolvableDesiredTarget = "runtime/unresolvable-desired-target";
      contentVerification = "runtime/content-verification";
      transitionRefused = "runtime/transition-refused";
      unresolvedRetirement = "runtime/unresolved-retirement";
      pendingRecovery = "runtime/pending-recovery";
    };
  };

  mkFilesystemIdentity =
    {
      namespace,
      destination,
    }:
    {
      inherit namespace destination;
      canonical = "${namespace}:${destination}";
    };

  mkEntry =
    {
      filesystemIdentity,
      authority,
      managedRoot,
      representation,
      retainedArtifactTarget,
      executor,
      cleanupStrategy,
      selfHealStrategy,
      provenance,
    }:
    {
      inherit schemaVersion;
      inherit
        filesystemIdentity
        authority
        managedRoot
        representation
        retainedArtifactTarget
        executor
        cleanupStrategy
        selfHealStrategy
        provenance
        ;
    };

  emit =
    entries:
    let
      manifestData = entries;
      manifestDocument = {
        inherit schemaVersion;
        diagnosticContract = runtimeDiagnostics;
        inherit entries;
      };
      manifestJson = builtins.toJSON manifestDocument;
    in
    {
      inherit manifestData manifestDocument manifestJson;
      # Store materialization belongs to the runtime, where pkgs.writeText can
      # preserve the manifest string context as closure references.
      manifestPath = null;
    };
in
{
  inherit
    schemaVersion
    diagnosticSchemaVersion
    ledger
    capabilities
    strategies
    executors
    runtimeDiagnostics
    mkFilesystemIdentity
    mkEntry
    emit
    ;
}
