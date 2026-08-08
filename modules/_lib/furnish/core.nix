{
  lib,
  contract,
  krisis,
  axiom,
  claimKeys,
  resolve,
  resolveSystem,
}:
let
  claimAttrs = lib.genAttrs claimKeys (_: null);

  reporter = krisis.mkReporter {
    formatDiagnostic =
      diagnostic:
      "furnish: ${diagnostic.code}: ${diagnostic.primary.label or "unlabeled"}: ${diagnostic.message}";
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

  # per-stage factories bound once. the curried `diagnostic` stays the exported
  # door; hot paths inside this file call these.
  shapeDiagnostic = diagnostic "shape-validation";
  selectionDiagnostic = diagnostic "ownership-selection";
  destinationDiagnostic = diagnostic "destination-validation";
  artifactDiagnostic = diagnostic "artifact-validation";
  executorDiagnostic = diagnostic "executor-validation";
  capabilityDiagnostic = diagnostic "capability-selection";

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
        (shapeDiagnostic "declaration-type" "unlabeled declaration"
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
          lib.optional condition (shapeDiagnostic code name reason);
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
            selectionDiagnostic "ownerships-disabled" (entryName declaration)
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
        destinationDiagnostic "invalid-${field}" (entryName declaration) "${field} must be an absolute path"
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
        destinationDiagnostic "outside-managed-root" (entryName declaration)
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

  executorSchema = axiom.schema.compile {
    allowUnknown = true;
    order = [
      "identity"
      "priority"
      "enabled"
      "protocolVersion"
      "capabilities"
      "materialize"
    ];
    onRecord =
      _executor:
      executorDiagnostic "executor-type" "unlabeled executor" "an executor must be an attribute set";
    fields = {
      identity = {
        required = true;
        validate = builtins.isString;
        onMissing =
          executor: executorDiagnostic "identity-type" (executorName executor) "identity must be a string";
        onInvalid =
          executor: _value:
          executorDiagnostic "identity-type" (executorName executor) "identity must be a string";
      };
      priority = {
        required = true;
        validate = builtins.isInt;
        onMissing =
          executor: executorDiagnostic "priority-type" (executorName executor) "priority must be an integer";
        onInvalid =
          executor: _value:
          executorDiagnostic "priority-type" (executorName executor) "priority must be an integer";
      };
      enabled = {
        validate = builtins.isBool;
        onInvalid =
          executor: _value:
          executorDiagnostic "enabled-type" (executorName executor) "enabled must be a boolean when present";
      };
      protocolVersion = {
        required = true;
        validate = builtins.isInt;
        onMissing =
          executor:
          executorDiagnostic "protocol-version-type" (executorName executor)
            "protocolVersion must be an integer";
        onInvalid =
          executor: _value:
          executorDiagnostic "protocol-version-type" (executorName executor)
            "protocolVersion must be an integer";
      };
      capabilities = {
        required = true;
        validate = value: builtins.isList value && lib.all builtins.isString value;
        onMissing =
          executor:
          executorDiagnostic "capabilities-shape" (executorName executor)
            "capabilities must be a list of strings";
        onInvalid =
          executor: _value:
          executorDiagnostic "capabilities-shape" (executorName executor)
            "capabilities must be a list of strings";
      };
      materialize = {
        required = true;
        onMissing =
          executor:
          executorDiagnostic "materialize-missing" (executorName executor)
            "materialize is required and remains lazy until selection";
      };
    };
  };

  executorDiagnostics = executor: (executorSchema executor).diagnostics;

  executorLess =
    a: b:
    if a.priority == b.priority then
      builtins.lessThan a.identity b.identity
    else
      builtins.lessThan a.priority b.priority;

  compileExecutorRegistry =
    executors:
    axiom.validation.finish failAll (
      axiom.registry.compile {
        registrations = executors;
        keyOf = executor: executor.identity;
        diagnosticsFor = executorDiagnostics;
        less = executorLess;
        onDuplicate =
          identity: _executors:
          executorDiagnostic "identity-duplicate" identity "executor identity must be unique";
      }
    );

  validateExecutors = executors: (compileExecutorRegistry executors).registrations;

  selectValidatedExecutor =
    executorSet: declaration:
    let
      required = requiredCapabilities declaration;
      observation = axiom.requirements.observe {
        inherit required;
        candidates = executorSet.ordered;
        enabled = executor: executor.enabled or false;
        providedBy = executor: executor.capabilities;
      };
      ordered = map (entry: entry.candidate) observation.qualified;
      enabledExecutors = builtins.sort (a: b: builtins.lessThan a.identity b.identity) (
        builtins.filter (executor: executor.enabled or false) executorSet.registrations
      );
      available = lib.concatMapStringsSep "; " (
        executor: "${executor.identity} [${lib.concatStringsSep ", " executor.capabilities}]"
      ) enabledExecutors;
    in
    if ordered == [ ] then
      fail (
        capabilityDiagnostic "no-capable-executor" (entryName declaration)
          "no enabled executor provides ${lib.concatStringsSep ", " required}; available: ${
            if available == "" then "none" else available
          }"
      )
    else
      builtins.head ordered;

  selectExecutor =
    executors: declaration: selectValidatedExecutor (compileExecutorRegistry executors) declaration;

  validateArtifact =
    selected: declaration: artifact:
    let
      name = entryName declaration;
      strategies = builtins.attrValues contract.strategies;
      diagnostics =
        if !builtins.isAttrs artifact then
          [
            (artifactDiagnostic "artifact-type" name "${selected.identity} must return an attribute set")
          ]
        else
          lib.optional (!(artifact ? retainedArtifactTarget)) (
            artifactDiagnostic "retained-target-missing" name
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
                artifactDiagnostic "retained-target-type" name
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
                artifactDiagnostic "cleanup-strategy" name
                  "${selected.identity} returned an unknown cleanup strategy"
              )
          ++ lib.optional (!(artifact ? cleanupStrategy)) (
            artifactDiagnostic "cleanup-strategy-missing" name
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
                artifactDiagnostic "self-heal-strategy" name
                  "${selected.identity} returned an unknown self-heal strategy"
              )
          ++ lib.optional (!(artifact ? selfHealStrategy)) (
            artifactDiagnostic "self-heal-strategy-missing" name
              "${selected.identity} must return selfHealStrategy"
          );
    in
    if diagnostics == [ ] then artifact else failAll diagnostics;

  materialize =
    executorSet: declaration:
    let
      selected = selectValidatedExecutor executorSet declaration;
      implementation =
        if builtins.isFunction selected.materialize then
          selected.materialize
        else
          fail (
            executorDiagnostic "materialize-type" selected.identity
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
        executorSet = compileExecutorRegistry executors;
        selected = krisis.withErrorContext "furnish: while selecting applicable declarations" (
          provider.selectApplicable validated ctx
        );
        normalized = map deriveDestination selected;
        ordered = builtins.sort identityLess normalized;
        index = buildIndex (map indexProjection ordered);
        manifestEntries = builtins.seq index (map (materialize executorSet) ordered);
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
