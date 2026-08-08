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

  # missing and wrong-typed are the same author mistake at this boundary, so a
  # field reports one diagnostic either way
  shapeField = code: reason: predicate: {
    required = true;
    validate = predicate;
    onMissing = declaration: shapeDiagnostic code (entryName declaration) reason;
    onInvalid = declaration: _value: shapeDiagnostic code (entryName declaration) reason;
  };

  presentShapeField = code: reason: predicate: {
    validate = predicate;
    onInvalid = declaration: _value: shapeDiagnostic code (entryName declaration) reason;
  };

  # open, because a declaration also carries its claim keys and whatever
  # provenance the caller attached
  declarationSchema = axiom.schema.compile {
    allowUnknown = true;
    onRecord =
      _value:
      shapeDiagnostic "declaration-type" "unlabeled declaration" "a declaration must be an attribute set";
    order = [
      "label"
      "filesystemNamespace"
      "authority"
      "managedRoot"
      "destination"
      "representation"
      "source"
      "provenance"
      "onConflict"
    ];
    fields = {
      label = shapeField "label-type" "label must be a string" builtins.isString;
      filesystemNamespace =
        shapeField "namespace-type" "filesystemNamespace must be a string"
          builtins.isString;
      authority = shapeField "authority-type" "authority must be an attribute set" builtins.isAttrs;
      managedRoot = shapeField "managed-root-type" "managedRoot must be a string" builtins.isString;
      destination = shapeField "destination-type" "destination must be a string" builtins.isString;
      representation = shapeField "representation-type" "representation must be a non-empty string" (
        value: builtins.isString value && value != ""
      );
      source = shapeField "source-type" "source must be an attribute set" builtins.isAttrs;
      provenance = presentShapeField "provenance-shape" "provenance values must be strings" (
        value: builtins.isAttrs value && lib.all builtins.isString (builtins.attrValues value)
      );
      onConflict =
        presentShapeField "on-conflict-value" "onConflict must be one of the declared conflict policies"
          (
            value:
            builtins.isString value && builtins.elem value (builtins.attrValues contract.conflictPolicies)
          );
    };
  };

  # the sub-record schemas run against `{ }` when their parent is missing or
  # wrong-typed, which is how a bad authority still reports its own fields
  authoritySchema =
    name:
    axiom.schema.compile {
      allowUnknown = true;
      onRecord = _value: shapeDiagnostic "authority-type" name "authority must be an attribute set";
      order = [
        "scope"
        "identity"
      ];
      fields = {
        scope = {
          required = true;
          validate =
            value:
            builtins.isString value
            && builtins.elem value [
              "user"
              "system"
            ];
          onMissing =
            _authority: shapeDiagnostic "authority-scope" name "authority.scope must be 'user' or 'system'";
          onInvalid =
            _authority: _value:
            shapeDiagnostic "authority-scope" name "authority.scope must be 'user' or 'system'";
        };
        identity = {
          required = true;
          validate = builtins.isString;
          onMissing =
            _authority:
            shapeDiagnostic "authority-identity" name "authority.identity must be a canonical string id";
          onInvalid =
            _authority: _value:
            shapeDiagnostic "authority-identity" name "authority.identity must be a canonical string id";
        };
      };
    };

  sourceSchema =
    name:
    axiom.schema.compile {
      allowUnknown = true;
      onRecord = _value: shapeDiagnostic "source-type" name "source must be an attribute set";
      order = [
        "kind"
        "value"
      ];
      fields = {
        kind = {
          required = true;
          validate = builtins.isString;
          onMissing = _source: shapeDiagnostic "source-kind" name "source.kind must be a string";
          onInvalid = _source: _value: shapeDiagnostic "source-kind" name "source.kind must be a string";
        };
        # no validator, so the payload stays unforced through validation
        value = {
          required = true;
          onMissing =
            _source:
            shapeDiagnostic "source-value" name "source.value is required and remains lazy during validation";
        };
      };
    };

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
      in
      axiom.validation.collect [
        (declarationSchema declaration).diagnostics
        (authoritySchema name authority).diagnostics
        (axiom.validation.optional
          (
            authority ? scope
            && builtins.isString authority.scope
            && authority.scope == "system"
            && authority ? identity
            && builtins.isString authority.identity
            && !lib.hasInfix "/" authority.identity
          )
          (
            shapeDiagnostic "system-authority-identity" name
              "a system authority identity must be the canonical '<system>/<name>' id"
          )
        )
        (sourceSchema name source).diagnostics
      ];

  validateShapes =
    declarations:
    axiom.validation.finish failAll (
      axiom.validation.fromDiagnostics (builtins.concatMap shapeDiagnostics declarations) declarations
    );

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

  # the filesystem identity is the index key, so collision detection is just
  # duplicate keying over the projections
  collisionIndex =
    projections:
    axiom.registry.compile {
      registrations = projections;
      keyOf = projection: projection.filesystemIdentity.canonical;
      less = claimantLess;
      onDuplicate =
        key: claimants:
        let
          sorted = builtins.sort claimantLess claimants;
        in
        collisionDiagnostic {
          code = "duplicate-filesystem-identity";
          message = "claimed by ${lib.concatMapStringsSep ", " renderClaimant sorted}";
          primary.label = key;
          context = {
            inherit ((builtins.head sorted)) filesystemIdentity;
            claimants = sorted;
          };
        };
    };

  collisionDiagnostics = projections: (collisionIndex projections).diagnostics;

  buildIndex = projections: (axiom.validation.finish failAll (collisionIndex projections)).byKey;

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

  strategyField = selected: name: code: field: noun: {
    required = true;
    validate =
      value: builtins.isString value && builtins.elem value (builtins.attrValues contract.strategies);
    onMissing =
      _artifact: artifactDiagnostic "${code}-missing" name "${selected.identity} must return ${field}";
    onInvalid =
      _artifact: _value: artifactDiagnostic code name "${selected.identity} returned an unknown ${noun}";
  };

  artifactSchema =
    selected: name:
    axiom.schema.compile {
      allowUnknown = true;
      onRecord =
        _value: artifactDiagnostic "artifact-type" name "${selected.identity} must return an attribute set";
      order = [
        "retainedArtifactTarget"
        "cleanupStrategy"
        "selfHealStrategy"
      ];
      fields = {
        retainedArtifactTarget = {
          required = true;
          validate = value: builtins.isString value || builtins.isPath value || lib.isDerivation value;
          onMissing =
            _artifact:
            artifactDiagnostic "retained-target-missing" name
              "${selected.identity} must return retainedArtifactTarget";
          onInvalid =
            _artifact: _value:
            artifactDiagnostic "retained-target-type" name
              "${selected.identity} must return a path-like retainedArtifactTarget";
        };
        cleanupStrategy =
          strategyField selected name "cleanup-strategy" "cleanupStrategy"
            "cleanup strategy";
        selfHealStrategy =
          strategyField selected name "self-heal-strategy" "selfHealStrategy"
            "self-heal strategy";
      };
    };

  validateArtifact =
    selected: declaration: artifact:
    axiom.validation.finish failAll (artifactSchema selected (entryName declaration) artifact);

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
