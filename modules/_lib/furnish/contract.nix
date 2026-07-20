_:
let
  schemaVersion = 1;

  capabilities = {
    symlink = "symlink";
    lifecycleBaseline = "lifecycle-baseline";
  };

  strategies = {
    exactSymlinkTarget = "exact-symlink-target";
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
      manifestJson = builtins.toJSON manifestData;
    in
    {
      inherit manifestData manifestJson;
      manifestPath =
        if manifestData == [ ] then
          null
        else
          builtins.toFile "furnish-desired-v${toString schemaVersion}.json" manifestJson;
    };
in
{
  inherit
    schemaVersion
    capabilities
    strategies
    mkFilesystemIdentity
    mkEntry
    emit
    ;
}
