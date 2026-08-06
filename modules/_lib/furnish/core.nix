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

  reporter = krisis.mkReporter {
    formatDiagnostic =
      diagnostic: "furnish: ${diagnostic.code}: ${diagnostic.primary.label}: ${diagnostic.message}";
  };

  renderDiagnostics = reporter.render;
  renderDiagnostic = reporter.renderOne;
  failAll = reporter.fail;
  fail = reporter.failOne;

  diagnostic =
    stage:
    let
      make = krisis.mkDiagnosticFactory {
        severity = "error";
        codePrefix = stage;
      };
    in
    code: entry: reason:
    make {
      inherit code;
      message = reason;
      primary.label = entry;
    };

  collisionDiagnostic = krisis.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "collision-detection";
  };

  entryName =
    declaration:
    if builtins.isAttrs declaration && declaration ? label && builtins.isString declaration.label then
      declaration.label
    else
      "unlabeled declaration";

  shapeDiagnostics =
    declaration:
    if !builtins.isAttrs declaration then
      [
        (diagnostic "shape-validation" "declaration-type" "unlabeled declaration"
          "a declaration must be an attribute set"
        )
      ]
    else
      let
        name = entryName declaration;
        authority =
          if declaration ? authority && builtins.isAttrs declaration.authority then
            declaration.authority
          else
            { };
        source =
          if declaration ? source && builtins.isAttrs declaration.source then declaration.source else { };
        provenanceValid =
          !(declaration ? provenance)
          || (
            builtins.isAttrs declaration.provenance
            && lib.all builtins.isString (builtins.attrValues declaration.provenance)
          );
        issue =
          condition: code: reason:
          lib.optional condition (diagnostic "shape-validation" code name reason);
      in
      issue (
        !(declaration ? label) || !builtins.isString declaration.label
      ) "label-type" "label must be a string"
      ++ issue (
        !(declaration ? filesystemNamespace) || !builtins.isString declaration.filesystemNamespace
      ) "namespace-type" "filesystemNamespace must be a string"
      ++ issue (
        !(declaration ? authority) || !builtins.isAttrs declaration.authority
      ) "authority-type" "authority must be an attribute set"
      ++ issue (
        !(authority ? scope)
        || !builtins.isString authority.scope
        || !(builtins.elem authority.scope [
          "user"
          "system"
        ])
      ) "authority-scope" "authority.scope must be 'user' or 'system'"
      ++ issue (
        !(authority ? identity) || !builtins.isString authority.identity
      ) "authority-identity" "authority.identity must be a canonical string id"
      ++
        issue
          (
            authority ? scope
            && builtins.isString authority.scope
            && authority.scope == "system"
            && authority ? identity
            && builtins.isString authority.identity
            && !lib.hasInfix "/" authority.identity
          )
          "system-authority-identity"
          "a system authority identity must be the canonical '<system>/<name>' id"
      ++ issue (
        !(declaration ? managedRoot) || !builtins.isString declaration.managedRoot
      ) "managed-root-type" "managedRoot must be a string"
      ++ issue (
        !(declaration ? destination) || !builtins.isString declaration.destination
      ) "destination-type" "destination must be a string"
      ++ issue (
        !(declaration ? representation)
        || !builtins.isString declaration.representation
        || declaration.representation == ""
      ) "representation-type" "representation must be a non-empty string"
      ++ issue (
        !(declaration ? source) || !builtins.isAttrs declaration.source
      ) "source-type" "source must be an attribute set"
      ++ issue (
        !(source ? kind) || !builtins.isString source.kind
      ) "source-kind" "source.kind must be a string"
      ++ issue (
        !(source ? value)
      ) "source-value" "source.value is required and remains lazy during validation"
      ++ issue (!provenanceValid) "provenance-shape" "provenance values must be strings"
      ++ issue (
        declaration ? onConflict
        && (
          !builtins.isString declaration.onConflict
          || !(builtins.elem declaration.onConflict (builtins.attrValues contract.conflictPolicies))
        )
      ) "on-conflict-value" "onConflict must be one of the declared conflict policies";

  validateShapes =
    declarations:
    let
      diagnostics = builtins.concatMap shapeDiagnostics declarations;
    in
    if diagnostics == [ ] then declarations else failAll diagnostics;

  validateShape = declaration: builtins.head (validateShapes [ declaration ]);

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

  # enabled selection runs its scope's declarations through the ownerships
  # public surface in one batched resolve per scope, with each declaration split
  # onto its own index key so an active declaration contributes its own value
  # and an inactive one simply leaves that key out. reading present-vs-empty
  # keeps selection from being a shared merge boundary and never forces a
  # dropped declaration's payload.
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
          selectScope =
            fn: rawCtx: scoped:
            let
              indexed = lib.imap0 (index: declaration: { inherit index declaration; }) scoped;
              resolved =
                if indexed == [ ] then
                  { }
                else
                  fn [
                    {
                      children = map (
                        { index, declaration }:
                        let
                          unit = ownershipUnit declaration;
                        in
                        unit
                        // {
                          value = {
                            ${"applied${toString index}"} = unit.value.entries;
                          };
                        }
                      ) indexed;
                    }
                  ] rawCtx;
            in
            builtins.concatMap (
              { index, declaration }:
              lib.optional ((resolved.${"applied${toString index}"} or [ ]) != [ ]) (applyEntry declaration)
            ) indexed;
        in
        selectScope resolveSystem {
          host = ctx.host or null;
        } (builtins.filter (declaration: declaration.authority.scope == "system") declarations)
        ++ selectScope resolve ctx (
          builtins.filter (declaration: declaration.authority.scope != "system") declarations
        );
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
    projections: builtins.groupBy (projection: projection.filesystemIdentity.canonical) projections;

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
      collisionDiagnostic {
        code = "duplicate-filesystem-identity";
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

  projectValidatedPrincipal =
    {
      declarations,
      principal,
      provider,
    }:
    let
      owned = builtins.filter (declaration: declaration.authority == principal.authority) declarations;
      selected = provider.selectApplicable owned principal.ctx;
    in
    map (declaration: indexProjection (deriveDestination declaration)) selected;

  projectPrincipal =
    {
      declarations,
      principal,
      provider ? defaultProvider,
    }:
    projectValidatedPrincipal {
      declarations = validateShapes declarations;
      inherit principal provider;
    };

  buildHostIndex =
    {
      declarations ? [ ],
      principals ? [ ],
      provider ? defaultProvider,
    }:
    let
      validated = validateShapes declarations;
    in
    buildIndex (
      builtins.seq validated (
        builtins.concatMap (
          principal:
          projectValidatedPrincipal {
            declarations = validated;
            inherit principal provider;
          }
        ) principals
      )
    );

  requiredCapabilities = declaration: [
    contract.capabilities.lifecycleBaseline
    declaration.representation
  ];

  executorName =
    executor:
    if builtins.isAttrs executor && executor ? identity && builtins.isString executor.identity then
      executor.identity
    else
      "unlabeled executor";

  executorDiagnostics =
    executor:
    if !builtins.isAttrs executor then
      [
        (diagnostic "executor-validation" "executor-type" "unlabeled executor"
          "an executor must be an attribute set"
        )
      ]
    else
      let
        name = executorName executor;
        issue =
          condition: code: reason:
          lib.optional condition (diagnostic "executor-validation" code name reason);
      in
      issue (
        !(executor ? identity) || !builtins.isString executor.identity
      ) "identity-type" "identity must be a string"
      ++ issue (
        !(executor ? priority) || !builtins.isInt executor.priority
      ) "priority-type" "priority must be an integer"
      ++ issue (
        executor ? enabled && !builtins.isBool executor.enabled
      ) "enabled-type" "enabled must be a boolean when present"
      ++ issue (
        !(executor ? protocolVersion) || !builtins.isInt executor.protocolVersion
      ) "protocol-version-type" "protocolVersion must be an integer"
      ++ issue (
        !(executor ? capabilities)
        || !builtins.isList executor.capabilities
        || !(lib.all builtins.isString executor.capabilities)
      ) "capabilities-shape" "capabilities must be a list of strings"
      ++ issue (
        !(executor ? materialize)
      ) "materialize-missing" "materialize is required and remains lazy until selection";

  validateExecutors =
    executors:
    let
      diagnostics = builtins.concatMap executorDiagnostics executors;
    in
    if diagnostics == [ ] then executors else failAll diagnostics;

  executorLess =
    a: b:
    if a.priority == b.priority then
      builtins.lessThan a.identity b.identity
    else
      builtins.lessThan a.priority b.priority;

  selectValidatedExecutor =
    executors: declaration:
    let
      required = requiredCapabilities declaration;
      capable = builtins.filter (
        executor:
        executor.enabled or false
        && lib.all (capability: builtins.elem capability executor.capabilities) required
      ) executors;
      ordered = builtins.sort executorLess capable;
      enabledExecutors = builtins.sort (a: b: builtins.lessThan a.identity b.identity) (
        builtins.filter (executor: executor.enabled or false) executors
      );
      available = lib.concatMapStringsSep "; " (
        executor: "${executor.identity} [${lib.concatStringsSep ", " executor.capabilities}]"
      ) enabledExecutors;
    in
    if ordered == [ ] then
      fail (
        diagnostic "capability-selection" "no-capable-executor" (entryName declaration)
          "no enabled executor provides ${lib.concatStringsSep ", " required}; available: ${
            if available == "" then "none" else available
          }"
      )
    else
      builtins.head ordered;

  selectExecutor =
    executors: declaration: selectValidatedExecutor (validateExecutors executors) declaration;

  validateArtifact =
    selected: declaration: artifact:
    let
      name = entryName declaration;
      strategies = builtins.attrValues contract.strategies;
      diagnostics =
        if !builtins.isAttrs artifact then
          [
            (diagnostic "artifact-validation" "artifact-type" name
              "${selected.identity} must return an attribute set"
            )
          ]
        else
          lib.optional (!(artifact ? retainedArtifactTarget)) (
            diagnostic "artifact-validation" "retained-target-missing" name
              "${selected.identity} must return retainedArtifactTarget"
          )
          ++
            lib.optional
              (
                artifact ? retainedArtifactTarget
                && !(
                  builtins.isString artifact.retainedArtifactTarget
                  || builtins.isPath artifact.retainedArtifactTarget
                  || lib.isDerivation artifact.retainedArtifactTarget
                )
              )
              (
                diagnostic "artifact-validation" "retained-target-type" name
                  "${selected.identity} must return a path-like retainedArtifactTarget"
              )
          ++
            lib.optional
              (
                artifact ? cleanupStrategy
                && (
                  !builtins.isString artifact.cleanupStrategy || !(builtins.elem artifact.cleanupStrategy strategies)
                )
              )
              (
                diagnostic "artifact-validation" "cleanup-strategy" name
                  "${selected.identity} returned an unknown cleanup strategy"
              )
          ++ lib.optional (!(artifact ? cleanupStrategy)) (
            diagnostic "artifact-validation" "cleanup-strategy-missing" name
              "${selected.identity} must return cleanupStrategy"
          )
          ++
            lib.optional
              (
                artifact ? selfHealStrategy
                && (
                  !builtins.isString artifact.selfHealStrategy
                  || !(builtins.elem artifact.selfHealStrategy strategies)
                )
              )
              (
                diagnostic "artifact-validation" "self-heal-strategy" name
                  "${selected.identity} returned an unknown self-heal strategy"
              )
          ++ lib.optional (!(artifact ? selfHealStrategy)) (
            diagnostic "artifact-validation" "self-heal-strategy-missing" name
              "${selected.identity} must return selfHealStrategy"
          );
    in
    if diagnostics == [ ] then artifact else failAll diagnostics;

  materialize =
    executors: declaration:
    let
      selected = selectValidatedExecutor executors declaration;
      implementation =
        if builtins.isFunction selected.materialize then
          selected.materialize
        else
          fail (
            diagnostic "executor-validation" "materialize-type" selected.identity
              "the selected executor materialize implementation must be a function"
          );
      artifact = validateArtifact selected declaration (
        krisis.withErrorContext "furnish: while materializing declaration '${entryName declaration}' with executor '${selected.identity}'" (
          implementation declaration
        )
      );
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
        validated = validateShapes declarations;
        checkedExecutors = validateExecutors executors;
        selected = krisis.withErrorContext "furnish: while selecting applicable declarations" (
          provider.selectApplicable validated ctx
        );
        normalized = map deriveDestination selected;
        ordered = builtins.sort identityLess normalized;
        index = buildIndex (map indexProjection ordered);
        manifestEntries = builtins.seq index (map (materialize checkedExecutors) ordered);
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
    shapeDiagnostics
    validateExecutors
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
