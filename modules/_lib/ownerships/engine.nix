# _lib/ownerships/engine.nix
#
# the pure ownerships engine is a fixed pipeline over an axis registry. it never
# inspects a claim value and never names an axis -- every axis owns its value
# type entirely and the engine only ever calls registered axis methods (top,
# narrow, observe, satisfiable, select, istop) and reads ctxkey to know whether the build
# ctx needs an entity for it. that is what lets a new axis of any value shape
# (a set axis, a predicate axis, a future role/trait axis) compose with zero
# edits here. roster access lives behind satisfiable/select only; compose/narrow
# are roster-independent, so the whole thing runs against a stubbed roster.
{ lib }:
let
  inherit (builtins)
    attrNames
    concatMap
    filter
    all
    length
    ;

  krisis = import ../krisis { inherit lib; };
  inherit (krisis) safeShape;

  # every registered axis at its identity - globally owned on all axes. a claim
  # missing an axis key falls back to that axis's top, so untagged == global.
  topClaim = registry: lib.mapAttrs (_: axis: axis.top) registry;

  # effective claim = parent's, narrowed per axis by this node's own claim. one
  # mapattrs over the registry, so the fold never names an axis; a missing key is
  # axis.top (the meet identity), which is why a claim can only narrow -- a
  # disjoint child collapses to an unsatisfiable value, caught by check, never a
  # silent widen.
  narrowClaim =
    registry: parent: own:
    lib.mapAttrs (name: axis: axis.narrow parent.${name} (own.${name} or axis.top)) registry;

  # walk the unit tree; emit one leaf { claim; value; } per config-bearing node,
  # each carrying its effective claim, plus optional label/source identity
  # metadata carried through untouched. nesting is `children`; a child
  # narrows its parent. nodes without a value contribute only their claim to
  # descendants. label/source ride as leaf siblings, never inside `value`, so
  # `strip` (which only ever pulls `.value`) drops them before merge for free.
  compose =
    registry: unit:
    let
      go =
        parent: node:
        let
          eff = narrowClaim registry parent (node.claim or { });
          self = lib.optional (node ? value) (
            {
              claim = eff;
              inherit (node) value;
            }
            // lib.optionalAttrs (node ? label) { inherit (node) label; }
            // lib.optionalAttrs (node ? source) { inherit (node) source; }
            // lib.optionalAttrs (node ? mergeProfile) { inherit (node) mergeProfile; }
          );
        in
        self ++ concatMap (go eff) (node.children or [ ]);
    in
    go (topClaim registry) unit;

  # stages register against a closed set of pipeline views. rejecting an
  # unknown view keeps a misspelled coverage rule from silently failing open.
  # a merged-output view can extend this set later with only the merged value
  # and safe metadata; no such boundary exists until an invariant needs it.
  knownViews = [
    "leaf"
    "tree"
    "survivors"
  ];

  validateStages =
    stages:
    let
      badView = builtins.filter (
        stage:
        !(
          builtins.isAttrs stage
          && stage ? view
          && builtins.isString stage.view
          && builtins.elem stage.view knownViews
        )
      ) stages;
      badRun = builtins.filter (
        stage:
        builtins.isAttrs stage
        && stage ? view
        && builtins.isString stage.view
        && builtins.elem stage.view knownViews
        && (!(stage ? run) || !builtins.isFunction stage.run)
      ) stages;
      invalidView = if badView == [ ] then null else builtins.head badView;
      shownView =
        if invalidView == null then
          null
        else if builtins.isAttrs invalidView && invalidView ? view then
          builtins.toJSON invalidView.view
        else
          "<missing>";
      invalidRun = if badRun == [ ] then null else builtins.head badRun;
    in
    if invalidView != null then
      throw "ownerships: unknown stage view ${shownView}"
    else if invalidRun != null then
      throw "ownerships: stage for view '${invalidRun.view}' must provide a 'run' function"
    else
      stages;

  stagesFor = view: stages: filter (stage: stage.view == view) (validateStages stages);

  # leaf stages retain one trace entry per leaf, but diagnostics flatten in
  # stage-registration order so one rule reports every leaf it rejects before
  # the next registered rule reports. the matrix is shared by both projections;
  # callbacks aren't evaluated twice.
  observeLeafStages =
    stages: registry: leaves:
    let
      matrix = map (stage: map (leaf: stage.run registry leaf) leaves) (stagesFor "leaf" stages);
      diagnostics = concatMap (row: lib.concatLists row) matrix;
    in
    {
      value = if diagnostics == [ ] then leaves else throwDiags diagnostics;
      trace = builtins.genList (i: concatMap (row: builtins.elemAt row i) matrix) (length leaves);
      reports = map (diagnosticsForStage: {
        view = "leaf";
        diagnostics = diagnosticsForStage;
      }) (map lib.concatLists matrix);
    };

  runLeafStages =
    stages: registry: leaves:
    (observeLeafStages stages registry leaves).value;

  # tree and survivor callbacks get different records on purpose. a tree rule
  # has no ctx to consult, while a survivor rule is handed the post-selection
  # set explicitly. cross-view order comes from the pipeline, never list order.
  observeViewStages =
    view: stages: args:
    let
      entries = map (stage: {
        inherit view;
        diagnostics = stage.run args;
      }) (stagesFor view stages);
      diagnostics = concatMap (entry: entry.diagnostics) entries;
      input = if view == "tree" then args.leaves else args.survivors;
    in
    {
      value = if diagnostics == [ ] then input else throwDiags diagnostics;
      trace = entries;
    };

  stageDiagnostics =
    view: stages: args:
    if view == "leaf" then
      concatMap (entry: entry.diagnostics) (observeLeafStages stages args.registry args.leaves).reports
    else
      concatMap (entry: entry.diagnostics) (observeViewStages view stages args).trace;

  # a diagnostic's unit is the leaf's raw config value -- it can carry a
  # package or a secret-backed value, so it's never safe to tojson/topretty in
  # full. identify it by label/source when the unit set one; otherwise fall
  # back to safeshape, which only ever lists attribute names and never touches
  # what they point to. axis/claims are always safe (polarity-set data, plain
  # strings), so those render in full.
  identifyUnit =
    d:
    if d.label or null != null then
      "unit '${d.label}'"
    else if d.source or null != null then
      "unit at ${d.source}"
    else
      "unlabeled unit ${safeShape d.unit}";

  mkOwnershipDiagnostic = krisis.mkDiagnosticFactory { severity = "error"; };

  toDiagnostic =
    diagnostic:
    mkOwnershipDiagnostic {
      code = diagnostic.kind;
      message = diagnostic.reason;
      primary =
        let
          pointer =
            lib.optionalAttrs (diagnostic.label or null != null) { inherit (diagnostic) label; }
            // lib.optionalAttrs (diagnostic.source or null != null) { inherit (diagnostic) source; };
        in
        if pointer == { } then null else pointer;
      context = diagnostic;
    };

  renderDiag =
    diagnostic:
    let
      domain = diagnostic.context;
      axisPart =
        if domain ? axis then
          "axis '${domain.axis}'"
        else if domain ? axes then
          "axes ${lib.concatStringsSep ", " domain.axes}"
        else
          null;
      claimsPart =
        if domain ? claims then
          "claim ${lib.generators.toPretty { multiline = false; } domain.claims}"
        else
          null;
      detail = lib.concatStringsSep ", " (
        lib.filter (part: part != null) [
          axisPart
          claimsPart
        ]
      );
    in
    "  - ${identifyUnit domain}: ${diagnostic.message}" + (if detail == "" then "" else " (${detail})");

  reporter = krisis.mkReporter {
    formatHeader = count: "ownerships: ${toString count} ownership error(s):";
    formatDiagnostic = renderDiag;
  };

  renderDiags = diagnostics: reporter.render (map toDiagnostic diagnostics);
  throwDiags = diagnostics: reporter.fail (map toDiagnostic diagnostics);

  # keep the leaves this build's ctx falls under on every axis; dropped leaves are
  # inactive -- silent, not an error. runs after check, so an impossible leaf
  # errors for everyone regardless of who is building, while a satisfiable leaf
  # that just doesn't match this build falls away quietly. a top (global) claim
  # owns everyone, so istop short-circuits it in before select runs -- that's
  # what keeps an untagged unit safe against a null or absent ctx entity, since
  # only a narrowing claim ever reaches the axis's select and reads the entity.
  # selection returns both the surviving leaves and a lazy account of the same
  # decisions. normal resolution projects only `selected`, so unit identity and
  # shape stay unforced unless a caller explicitly asks for the trace.
  observeSelect =
    registry: ctx: leaves:
    let
      traced = map (
        leaf:
        let
          axisResults = lib.mapAttrs (
            name: axis:
            let
              claim = leaf.claim.${name};
              observation = axis.observe claim;
              selection =
                if axis.isTop claim then
                  {
                    selected = true;
                    decision = "global";
                  }
                else
                  let
                    selected = krisis.withErrorContext "ownerships: while evaluating axis '${name}' selector for unit ${safeShape leaf.value}" (observation.select ctx)
                    .selected;
                  in
                  {
                    inherit selected;
                    decision = if selected then "selected" else "rejected";
                  };
            in
            {
              inherit claim;
              inherit (selection) selected decision;
              details = removeAttrs observation [ "select" ];
            }
          ) registry;
          selected = all (name: axisResults.${name}.selected) (attrNames registry);
        in
        {
          inherit leaf axisResults selected;
          report = {
            identity = identifyUnit {
              unit = leaf.value;
              label = leaf.label or null;
              source = leaf.source or null;
            };
            effectiveClaim = leaf.claim;
            inherit axisResults selected;
            rejectedBy = filter (name: !axisResults.${name}.selected) (attrNames registry);
            preMergeContribution =
              if selected then
                {
                  stage = "pre-merge";
                  meaning = "paths this leaf offers into the merge; not post-merge attribution";
                  offeredPaths =
                    if builtins.isAttrs leaf.value && (leaf.value.type or null) != "derivation" then
                      attrNames leaf.value
                    else
                      [ "<root>" ];
                  shape = safeShape leaf.value;
                }
              else
                null;
          };
        }
      ) leaves;
    in
    {
      selected = map (entry: entry.leaf) (filter (entry: entry.selected) traced);
      trace = map (entry: entry.report) traced;
    };

  runSelect =
    registry: ctx: leaves:
    (observeSelect registry ctx leaves).selected;

  strip = leaves: map (leaf: leaf.value) leaves;

  # identity names the authoring leaf through identifyunit; it doesn't inherit
  # from a parent. owners are that leaf's effective claim after every parent and
  # child meet, so narrowing flows in while identity does not. an untagged set
  # axis remains its exclude [] top - global and narrowed leaves are distinct
  # contributors at one path. merge preserves these claims as opaque data and
  # never interprets or materializes them.
  stripForMerge =
    leaves:
    map (leaf: {
      inherit (leaf) value;
      contributor = {
        identity = identifyUnit {
          unit = leaf.value;
          label = leaf.label or null;
          source = leaf.source or null;
        };
        owners = leaf.claim;
      }
      // lib.optionalAttrs (leaf ? mergeProfile) { inherit (leaf) mergeProfile; };
    }) leaves;

  # per axis, the effective claim must be satisfiable against the roster; an empty
  # set (a disjoint nest or an unknown name) is impossible. diagnostic is the
  # per-axis form { unit; axis; claims; reason }.
  satisfiableCheck =
    registry: leaf:
    concatMap (
      name:
      lib.optional (!registry.${name}.satisfiable leaf.claim.${name}) {
        kind = "impossible";
        unit = leaf.value;
        label = leaf.label or null;
        source = leaf.source or null;
        axis = name;
        claims = leaf.claim;
        reason = "axis '${name}' claim can never be satisfied (disjoint nest or unknown name)";
      }
    ) (attrNames registry);

  # relations are registered data over two set-like axes. the checker owns the
  # shared skip/rescue/compatibility semantics, while axis names, roster data,
  # and diagnostic wording arrive entirely through the registration.
  mkRelationCheck =
    relation: registry: leaf:
    let
      leftName = relation.leftAxis;
      rightName = relation.rightAxis;
      leftAxis = registry.${leftName};
      rightAxis = registry.${rightName};
      leftClaim = leaf.claim.${leftName};
      rightClaim = leaf.claim.${rightName};
      leftMembers = (leftAxis.observe leftClaim).materializedMembers;
      rightMembers = (rightAxis.observe rightClaim).materializedMembers;
      rescued =
        builtins.any (member: builtins.elem member relation.unknown.left) leftMembers
        || builtins.any (member: builtins.elem member relation.unknown.right) rightMembers;
      compatible = builtins.any (
        left: builtins.any (right: relation.compatible left right) rightMembers
      ) leftMembers;
    in
    if
      leftAxis.isTop leftClaim
      || rightAxis.isTop rightClaim
      || leftMembers == [ ]
      || rightMembers == [ ]
      || rescued
      || compatible
    then
      [ ]
    else
      [
        {
          kind = "impossible";
          unit = leaf.value;
          label = leaf.label or null;
          source = leaf.source or null;
          axes = [
            leftName
            rightName
          ];
          claims = leaf.claim;
          reason = relation.reason leftMembers rightMembers;
        }
      ];

  defaultStages = [
    {
      view = "leaf";
      run = satisfiableCheck;
    }
  ];

  # the build ctx must carry an entity only for an axis that (a) reads one
  # (ctxkey != null) and (b) is actually narrowed on by some leaf. a fully
  # untagged (global) axis reads no entity in select, so a null or absent ctx
  # entry for it is fine -- that's what lets a bare, owner-less spec resolve with
  # no build context at all. a claim that does narrow on an axis whose entity is
  # missing or present-but-null is still a loud, structured error. the demand is
  # derived per-resolve from the composed leaves, so it never consults the
  # registry as a whole and still never hardcodes host, user, or when.
  observeCtx =
    registry: ctx: leaves:
    let
      entries = map (
        leaf:
        let
          requirements = lib.mapAttrs (
            name: axis:
            let
              key = axis.ctxKey;
            in
            {
              inherit key;
              required = key != null && !(axis.isTop leaf.claim.${name});
              available = if key == null then null else ctx ? ${key} && ctx.${key} != null;
            }
          ) registry;
          diagnostics = concatMap (
            name:
            let
              requirement = requirements.${name};
            in
            lib.optional (requirement.required && !requirement.available) {
              kind = "missing-ctx";
              unit = leaf.value;
              label = leaf.label or null;
              source = leaf.source or null;
              axis = name;
              claims = leaf.claim;
              reason = "axis '${name}' is narrowed on by claim ${
                lib.generators.toPretty { multiline = false; } leaf.claim.${name}
              } but the build ctx provides no entity for key '${requirement.key}' -- only untagged (global) claims resolve without a build context";
            }
          ) (attrNames registry);
        in
        {
          inherit diagnostics requirements;
        }
      ) leaves;
      diagnostics = concatMap (entry: entry.diagnostics) entries;
    in
    {
      value = if diagnostics == [ ] then ctx else throwDiags diagnostics;
      trace = map (entry: entry.requirements) entries;
    };

  # prepared leaves have already passed leaf and tree checks. matrix projection
  # uses this boundary too, so context demand, selection, and survivor rules
  # can't drift away from ordinary resolution.
  selectPrepared =
    {
      registry,
      stages,
      ctx,
    }:
    leaves:
    let
      ctxObservation = observeCtx registry ctx leaves;
      ctx' = ctxObservation.value;
      selection = observeSelect registry ctx' leaves;
      survivorObservation = observeViewStages "survivors" stages {
        inherit registry;
        ctx = ctx';
        survivors = selection.selected;
      };
      survivors = survivorObservation.value;
    in
    {
      ctx = ctx';
      inherit survivors;
      selectionTrace = selection.trace;
      ctxTrace = ctxObservation.trace;
      survivorTrace = survivorObservation.trace;
    };

  # the fixed order is leaf -> tree -> ctx -> select -> survivors -> strip ->
  # merge. each diagnostic phase aggregates fully before throwing, while a
  # failed earlier phase prevents every later phase from being evaluated.
  # `prepare` covers the ctx-independent half (compose, leaf and tree checks)
  # and `applyPrepared` the per-ctx tail (ctx demand, select, survivors, strip,
  # merge). callers resolving one unit set for many contexts -- the program
  # surface's per-user slices -- build the prepared half once and reuse it.
  prepare =
    {
      registry,
      merge,
      stages ? defaultStages,
    }:
    unit:
    let
      leaves = compose registry unit;
      leafObservation = observeLeafStages stages registry leaves;
      leafChecked = leafObservation.value;
      treeObservation = observeViewStages "tree" stages {
        inherit registry;
        leaves = leafChecked;
      };
      treeChecked = treeObservation.value;
    in
    {
      inherit registry merge stages;
      leaves = treeChecked;
      leafObservation = removeAttrs leafObservation [ "value" ];
      treeTrace = treeObservation.trace;
    };

  applyPrepared =
    {
      registry,
      merge,
      stages,
      leaves,
      leafObservation,
      treeTrace,
    }:
    ctx:
    let
      selected = selectPrepared {
        inherit registry stages ctx;
      } leaves;
      merged = merge (stripForMerge selected.survivors);
    in
    {
      inherit (merged) value;
      mergeProvenance = merged.provenance;
      trace = builtins.genList (
        i:
        (builtins.elemAt selected.selectionTrace i)
        // {
          checkResults = builtins.elemAt leafObservation.trace i;
          ctxRequirements = builtins.elemAt selected.ctxTrace i;
        }
      ) (length selected.selectionTrace);
      stageReports = {
        leaf = leafObservation.reports;
        tree = treeTrace;
        survivors = selected.survivorTrace;
      };
      # kept lazy so a failing trace can expose the exact text its leaf phase
      # would throw without forcing the phase's value projection.
      diagnosticText.leaf =
        let
          diagnostics = concatMap (report: report.diagnostics) leafObservation.reports;
        in
        if diagnostics == [ ] then null else renderDiags diagnostics;
    };

  pipeline = args: unit: applyPrepared (prepare (removeAttrs args [ "ctx" ]) unit) args.ctx;
  resolve = args: unit: (pipeline args unit).value;
  trace = pipeline;
in
{
  inherit
    compose
    strip
    stripForMerge
    resolve
    trace
    satisfiableCheck
    mkRelationCheck
    defaultStages
    knownViews
    stageDiagnostics
    selectPrepared
    prepare
    applyPrepared
    topClaim
    identifyUnit
    # exported so a golden-error test can assert its exact output against
    # crafted diagnostics while trace identity uses the same helper.
    renderDiags
    throwDiags
    ;
  check = runLeafStages;
  select = runSelect;
}
