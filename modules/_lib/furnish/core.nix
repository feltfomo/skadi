{
  lib,
  contract,
  resolve,
  resolveSystem,
}:
let
  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];
  claimAttrs = lib.genAttrs claimKeys (_: null);

  renderDiagnostic =
    diagnostic:
    "furnish: ${diagnostic.stage}/${diagnostic.code}: ${diagnostic.entry}: ${diagnostic.reason}";

  fail = diagnostic: throw (renderDiagnostic diagnostic);

  diagnostic = stage: code: entry: reason: {
    inherit
      stage
      code
      entry
      reason
      ;
  };

  entryName = declaration: declaration.label or "unlabeled declaration";

  require =
    declaration: condition: code: reason:
    if condition then
      true
    else
      fail (diagnostic "shape-validation" code (entryName declaration) reason);

  validateShape =
    declaration:
    let
      isAttrs = builtins.isAttrs declaration;
      checked =
        require declaration isAttrs "declaration-type" "a declaration must be an attribute set"
        && require declaration (
          declaration ? label && builtins.isString declaration.label
        ) "label-type" "label must be a string"
        && require declaration (
          declaration ? filesystemNamespace && builtins.isString declaration.filesystemNamespace
        ) "namespace-type" "filesystemNamespace must be a string"
        && require declaration (
          declaration ? authority && builtins.isAttrs declaration.authority
        ) "authority-type" "authority must be an attribute set"
        && require declaration (
          declaration.authority ? scope
          && builtins.elem declaration.authority.scope [
            "user"
            "system"
          ]
        ) "authority-scope" "authority.scope must be 'user' or 'system'"
        && require declaration (
          declaration.authority ? identity && builtins.isString declaration.authority.identity
        ) "authority-identity" "authority.identity must be a canonical string id"
        &&
          require declaration
            (declaration.authority.scope != "system" || lib.hasInfix "/" declaration.authority.identity)
            "system-authority-identity"
            "a system authority identity must be the canonical '<system>/<name>' id"
        && require declaration (
          declaration ? managedRoot && builtins.isString declaration.managedRoot
        ) "managed-root-type" "managedRoot must be a string"
        && require declaration (
          declaration ? destination && builtins.isString declaration.destination
        ) "destination-type" "destination must be a string"
        && require declaration (
          declaration ? representation && builtins.isString declaration.representation
        ) "representation-type" "representation must be a string"
        && require declaration (
          declaration ? source
          && builtins.isAttrs declaration.source
          && declaration.source ? kind
          && builtins.isString declaration.source.kind
          && declaration.source ? value
        ) "source-shape" "source must carry a string kind and a lazy value"
        && require declaration (
          !(declaration ? provenance)
          || (
            builtins.isAttrs declaration.provenance
            && lib.all builtins.isString (builtins.attrValues declaration.provenance)
          )
        ) "provenance-shape" "provenance values must be strings";
    in
    builtins.seq checked declaration;

  ownershipUnit =
    declaration:
    (builtins.intersectAttrs claimAttrs declaration)
    // {
      inherit (declaration) label;
      value.entries = [ (removeAttrs declaration claimKeys) ];
    };

  # Off mode leans on this staying pure and roster-free, so it must never
  # resolve or touch the payload -- just read the claim vocabulary.
  isOwnerTagged = declaration: builtins.intersectAttrs claimAttrs declaration != { };

  # A surviving declaration keeps only its own fields; its claim keys are the
  # ownership vocabulary and never ride into a manifest entry.
  applyEntry = declaration: removeAttrs declaration claimKeys;

  # Enabled selection runs one unit at a time through the ownerships public
  # surface: an active unit resolves to its own value, an inactive one resolves
  # to empty. Reading present-vs-empty keeps selection from being a shared merge
  # gate and never forces a dropped unit's payload.
  mkEnabledProvider =
    {
      resolve,
      resolveSystem,
    }:
    {
      inherit isOwnerTagged;
      selectApplicable =
        declarations: ctx:
        let
          applies =
            declaration:
            let
              unit = ownershipUnit declaration;
              resolved =
                if declaration.authority.scope == "system" then
                  resolveSystem [ unit ] { host = ctx.host or null; }
                else
                  resolve [ unit ] ctx;
            in
            (resolved.entries or [ ]) != [ ];
        in
        map applyEntry (builtins.filter applies declarations);
    };

  # Off mode has no roster to select against, so an untagged (globally owned)
  # declaration passes untouched while an owner-tagged one is a loud author
  # error -- never a silent identity pass.
  offProvider = {
    inherit isOwnerTagged;
    selectApplicable =
      declarations: _ctx:
      map (
        declaration:
        if isOwnerTagged declaration then
          fail (
            diagnostic "ownership-selection" "ownerships-disabled" (entryName declaration)
              "ownership claim requires the ownerships subsystem; enable ownerships or remove the claim"
          )
        else
          applyEntry declaration
      ) declarations;
  };

  normalizeAbsolute =
    declaration: field: value:
    let
      parts = lib.splitString "/" (lib.removePrefix "/" value);
      invalid =
        value == ""
        || !lib.hasPrefix "/" value
        || lib.any (part: part == "" || part == "." || part == "..") parts;
    in
    if invalid then
      fail (
        diagnostic "destination-validation" "invalid-${field}" (entryName declaration)
          "${field} must be a normalized absolute path without empty, '.' or '..' segments"
      )
    else
      "/${lib.concatStringsSep "/" parts}";

  deriveDestination =
    declaration:
    let
      root = normalizeAbsolute declaration "managed-root" declaration.managedRoot;
      absolute =
        if lib.hasPrefix "/" declaration.destination then
          normalizeAbsolute declaration "destination" declaration.destination
        else
          normalizeAbsolute declaration "destination" "${root}/${declaration.destination}";
      beneathRoot = absolute != root && lib.hasPrefix "${root}/" absolute;
    in
    if !beneathRoot then
      fail (
        diagnostic "destination-validation" "outside-managed-root" (entryName declaration)
          "destination must be beneath its managed root"
      )
    else
      declaration
      // {
        managedRoot = root;
        filesystemIdentity = contract.mkFilesystemIdentity {
          namespace = declaration.filesystemNamespace;
          destination = absolute;
        };
      };

  identityLess =
    a: b: builtins.lessThan a.filesystemIdentity.canonical b.filesystemIdentity.canonical;

  findCollision =
    entries:
    if builtins.length entries < 2 then
      null
    else
      let
        left = builtins.head entries;
        rest = builtins.tail entries;
        right = builtins.head rest;
      in
      if left.filesystemIdentity.canonical == right.filesystemIdentity.canonical then
        {
          inherit left right;
        }
      else
        findCollision rest;

  checkCollisions =
    entries:
    let
      collision = findCollision entries;
    in
    if collision == null then
      entries
    else
      fail (
        diagnostic "collision-detection" "duplicate-filesystem-identity"
          "${entryName collision.left}, ${entryName collision.right}"
          "both declarations claim ${collision.left.filesystemIdentity.canonical}"
      );

  requiredCapabilities = declaration: [
    contract.capabilities.lifecycleBaseline
    declaration.representation
  ];

  executorLess =
    a: b:
    if a.priority == b.priority then
      builtins.lessThan a.identity b.identity
    else
      builtins.lessThan a.priority b.priority;

  selectExecutor =
    executors: declaration:
    let
      required = requiredCapabilities declaration;
      capable = builtins.filter (
        executor:
        executor.enabled or false
        && lib.all (capability: builtins.elem capability executor.capabilities) required
      ) executors;
      ordered = builtins.sort executorLess capable;
    in
    if ordered == [ ] then
      fail (
        diagnostic "capability-selection" "no-capable-executor" (entryName declaration)
          "no enabled executor provides ${lib.concatStringsSep ", " required}"
      )
    else
      builtins.head ordered;

  materialize =
    executors: declaration:
    let
      selected = selectExecutor executors declaration;
      artifact = selected.materialize declaration;
      retainedArtifactTarget = toString artifact.retainedArtifactTarget;
    in
    contract.mkEntry {
      inherit (declaration)
        filesystemIdentity
        authority
        managedRoot
        representation
        ;
      inherit retainedArtifactTarget;
      executor = {
        inherit (selected) identity;
        inherit (selected) protocolVersion;
      };
      inherit (artifact) cleanupStrategy;
      inherit (artifact) selfHealStrategy;
      provenance = {
        declaration = declaration.label;
        source = (declaration.provenance or { }).source or "unknown";
      };
    };

  defaultProvider = mkEnabledProvider {
    inherit resolve resolveSystem;
  };

  compile =
    {
      declarations ? [ ],
      executors ? [ ],
      ctx ? { },
      raw ? { },
      provider ? defaultProvider,
    }:
    if declarations == [ ] then
      (contract.emit [ ])
      // {
        inherit raw;
      }
    else
      let
        validated = map validateShape declarations;
        # Force only the checked authority metadata so every cheap shape error
        # wins before ownership selection without touching a source payload.
        shapeChecked = builtins.deepSeq (map (
          declaration: declaration.authority.scope
        ) validated) validated;
        selected = provider.selectApplicable shapeChecked ctx;
        normalized = map deriveDestination selected;
        ordered = builtins.sort identityLess normalized;
        collisionChecked = checkCollisions ordered;
        manifestEntries = map (materialize executors) collisionChecked;
      in
      (contract.emit manifestEntries)
      // {
        inherit raw;
      };
in
{
  inherit
    compile
    diagnostic
    renderDiagnostic
    validateShape
    isOwnerTagged
    mkEnabledProvider
    offProvider
    deriveDestination
    checkCollisions
    selectExecutor
    ;
}
