{
  lib,
  contract,
  krisis,
  claimKeys,
  resolve,
  resolveSystem,
}:
let
  claimAttrs = lib.genAttrs claimKeys (_: null);

  renderArgs = diagnostics: {
    inherit diagnostics;
    formatDiagnostic =
      diagnostic: "furnish: ${diagnostic.code}: ${diagnostic.primary.label}: ${diagnostic.message}";
  };

  renderDiagnostics = diagnostics: krisis.renderDiagnostics (renderArgs diagnostics);
  renderDiagnostic = diagnostic: renderDiagnostics [ diagnostic ];
  failAll = diagnostics: krisis.throwDiagnostics (renderArgs diagnostics);
  fail = diagnostic: failAll [ diagnostic ];

  diagnostic =
    stage: code: entry: reason:
    krisis.mkDiagnostic {
      severity = "error";
      code = "${stage}/${code}";
      message = reason;
      primary.label = entry;
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
        ) "provenance-shape" "provenance values must be strings"
        && require declaration (
          !(declaration ? onConflict)
          || builtins.elem declaration.onConflict (builtins.attrValues contract.conflictPolicies)
        ) "on-conflict-value" "onConflict must be one of the declared conflict policies";
    in
    builtins.seq checked declaration;

  ownershipUnit =
    declaration:
    (builtins.intersectAttrs claimAttrs declaration)
    // {
      inherit (declaration) label;
      value.entries = [ (removeAttrs declaration claimKeys) ];
    };

  # off mode leans on this staying pure and roster-free, so it must never
  # resolve or touch the payload -- just read the claim vocabulary.
  isOwnerTagged = declaration: builtins.intersectAttrs claimAttrs declaration != { };

  # a surviving declaration keeps only its own fields; its claim keys are the
  # ownership vocabulary and never ride into a manifest entry.
  applyEntry = declaration: removeAttrs declaration claimKeys;

  # enabled selection runs one unit at a time through the ownerships public
  # surface, where an active unit resolves to its own value and an inactive one
  # resolves to empty. reading present-vs-empty keeps selection from being a
  # shared merge boundary and never forces a dropped unit's payload.
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

  # off mode has no roster to select against, so an untagged (globally owned)
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
      step =
        state: part:
        if part == "" || part == "." then
          state
        else if part == ".." then
          if state.parts == [ ] then
            state // { escaped = true; }
          else
            state // { parts = lib.init state.parts; }
        else
          state // { parts = state.parts ++ [ part ]; };
      normalized = builtins.foldl' step {
        parts = [ ];
        escaped = false;
      } (lib.splitString "/" (lib.removePrefix "/" value));
      path = "/${lib.concatStringsSep "/" normalized.parts}";
    in
    if value == "" || !lib.hasPrefix "/" value then
      fail (
        diagnostic "destination-validation" "invalid-${field}" (entryName declaration)
          "${field} must be an absolute path"
      )
    else
      normalized // { inherit path; };

  deriveDestination =
    declaration:
    let
      rootResult = normalizeAbsolute declaration "managed-root" declaration.managedRoot;
      root = rootResult.path;
      destinationResult = normalizeAbsolute declaration "destination" (
        if lib.hasPrefix "/" declaration.destination then
          declaration.destination
        else
          "${root}/${declaration.destination}"
      );
      absolute = destinationResult.path;
      beneathRoot =
        !rootResult.escaped
        && !destinationResult.escaped
        && root != "/"
        && absolute != "/"
        && absolute != root
        && lib.hasPrefix "${root}/" absolute;
    in
    if !beneathRoot then
      fail (
        diagnostic "destination-validation" "outside-managed-root" (entryName declaration)
          "destination must remain beneath its managed root after lexical normalization"
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

  indexProjection = declaration: {
    inherit (declaration) filesystemIdentity authority managedRoot;
    provenance = {
      declaration = entryName declaration;
      source = (declaration.provenance or { }).source or "unknown";
    };
  };

  claimantKey =
    claimant:
    "${claimant.authority.scope}:${claimant.authority.identity}:${claimant.provenance.source}:${claimant.provenance.declaration}";

  claimantLess = a: b: builtins.lessThan (claimantKey a) (claimantKey b);

  renderClaimant =
    claimant:
    "${claimant.authority.scope}/${claimant.authority.identity} (${claimant.provenance.declaration} at ${claimant.provenance.source})";

  groupProjections =
    projections:
    builtins.foldl'
      (
        groups: projection:
        let
          key = projection.filesystemIdentity.canonical;
        in
        groups // { ${key} = (groups.${key} or [ ]) ++ [ projection ]; }
      )
      { }
      (
        builtins.sort (
          a: b:
          if a.filesystemIdentity.canonical == b.filesystemIdentity.canonical then
            claimantLess a b
          else
            identityLess a b
        ) projections
      );

  collisionDiagnostics =
    projections:
    let
      groups = groupProjections projections;
    in
    map (
      key:
      let
        claimants = builtins.sort claimantLess groups.${key};
      in
      krisis.mkDiagnostic {
        severity = "error";
        code = "collision-detection/duplicate-filesystem-identity";
        message = "claimed by ${lib.concatMapStringsSep ", " renderClaimant claimants}";
        primary.label = key;
        context = {
          inherit ((builtins.head claimants)) filesystemIdentity;
          inherit claimants;
        };
      }
    ) (builtins.filter (key: builtins.length groups.${key} > 1) (builtins.attrNames groups));

  buildIndex =
    projections:
    let
      groups = groupProjections projections;
      diagnostics = collisionDiagnostics projections;
    in
    if diagnostics != [ ] then
      failAll diagnostics
    else
      lib.mapAttrs (_: claimants: builtins.head claimants) groups;

  projectPrincipal =
    {
      declarations,
      principal,
      provider ? defaultProvider,
    }:
    let
      validated = map validateShape declarations;
      shapeChecked = builtins.deepSeq (map (
        declaration: declaration.authority.scope
      ) validated) validated;
      owned = builtins.filter (declaration: declaration.authority == principal.authority) shapeChecked;
      selected = provider.selectApplicable owned principal.ctx;
    in
    map (declaration: indexProjection (deriveDestination declaration)) selected;

  buildHostIndex =
    {
      declarations ? [ ],
      principals ? [ ],
      provider ? defaultProvider,
    }:
    buildIndex (
      builtins.concatMap (
        principal: projectPrincipal { inherit declarations principal provider; }
      ) principals
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
      # a declaration that names no policy still lands one in the manifest, so
      # nothing reading the entry has to know what an absent field would mean.
      onConflict = declaration.onConflict or contract.conflictPolicies.error;
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
        # force only the checked authority metadata so every cheap shape error
        # wins before ownership selection without touching a source payload.
        shapeChecked = builtins.deepSeq (map (
          declaration: declaration.authority.scope
        ) validated) validated;
        selected = provider.selectApplicable shapeChecked ctx;
        normalized = map deriveDestination selected;
        ordered = builtins.sort identityLess normalized;
        index = buildIndex (map indexProjection ordered);
        manifestEntries = builtins.seq index (map (materialize executors) ordered);
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
    renderDiagnostics
    validateShape
    isOwnerTagged
    mkEnabledProvider
    offProvider
    deriveDestination
    indexProjection
    collisionDiagnostics
    buildHostIndex
    projectPrincipal
    selectExecutor
    ;
}
