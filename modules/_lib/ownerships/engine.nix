# _lib/ownerships/engine.nix
#
# The pure ownerships engine: a fixed pipeline over an axis REGISTRY. It never
# inspects a claim value and never names an axis -- every axis owns its value
# type entirely and the engine only ever calls the axis's methods (top, narrow,
# satisfiable, select) and reads its declared ctxKey to know whether the build
# ctx needs an entity for it. That is what lets a new axis of any value shape
# (a set axis, a predicate axis, a future role/trait axis) compose with zero
# edits here. Roster access lives behind satisfiable/select only; compose/narrow
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

  inherit (import ./safe-render.nix { inherit lib; }) safeShape;

  # every registered axis at its identity: globally owned on all axes. a claim
  # missing an axis key falls back to that axis's top, so untagged == global.
  topClaim = registry: lib.mapAttrs (_: axis: axis.top) registry;

  # effective claim = parent's, narrowed per axis by this node's own claim. one
  # mapAttrs over the registry, so the fold never names an axis; a missing key is
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
          );
        in
        self ++ concatMap (go eff) (node.children or [ ]);
    in
    go (topClaim registry) unit;

  # Checks keep their per-leaf results beside the unchanged leaf list. The
  # ordinary path projects `value`; a trace reads the already-computed lists.
  observeCheck =
    subChecks: registry: leaves:
    let
      entries = map (leaf: {
        inherit leaf;
        diagnostics = concatMap (c: c registry leaf) subChecks;
      }) leaves;
      diagnostics = concatMap (entry: entry.diagnostics) entries;
    in
    {
      value = if diagnostics == [ ] then leaves else throw (renderDiags diagnostics);
      trace = map (entry: entry.diagnostics) entries;
    };

  runCheck =
    subChecks: registry: leaves:
    (observeCheck subChecks registry leaves).value;

  # a diagnostic's unit is the leaf's raw config value -- it can carry a
  # package or a secret-backed value, so it's never safe to toJSON/toPretty in
  # full. identify it by label/source when the unit set one; otherwise fall
  # back to safeShape, which only ever lists attribute names and never touches
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

  renderDiag =
    d:
    let
      axisPart =
        if d ? axis then
          "axis '${d.axis}'"
        else if d ? axes then
          "axes ${lib.concatStringsSep ", " d.axes}"
        else
          null;
      claimsPart =
        if d ? claims then "claim ${lib.generators.toPretty { multiline = false; } d.claims}" else null;
      detail = lib.concatStringsSep ", " (
        lib.filter (x: x != null) [
          axisPart
          claimsPart
        ]
      );
    in
    "  - ${identifyUnit d}: ${d.reason}" + (if detail == "" then "" else " (${detail})");

  renderDiags =
    diags:
    "ownerships: ${toString (length diags)} ownership error(s):\n"
    + lib.concatMapStringsSep "\n" renderDiag diags;

  # keep the leaves this build's ctx falls under on every axis; dropped leaves are
  # inactive -- silent, not an error. runs AFTER check, so an impossible leaf
  # errors for everyone regardless of who is building, while a satisfiable leaf
  # that just doesn't match this build falls away quietly. a top (global) claim
  # owns everyone, so isTop short-circuits it in before select runs -- that's
  # what keeps an untagged unit safe against a null or absent ctx entity, since
  # only a narrowing claim ever reaches the axis's select and reads the entity.
  # Selection returns both the surviving leaves and a lazy account of the same
  # decisions. Normal resolution projects only `selected`, so unit identity and
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
                  observation.select ctx;
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

  defaultChecks = [ satisfiableCheck ];

  # the build ctx must carry an entity only for an axis that (a) reads one
  # (ctxKey != null) and (b) is actually narrowed on by some leaf. a fully
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
      value = if diagnostics == [ ] then ctx else throw (renderDiags diagnostics);
      trace = map (entry: entry.requirements) entries;
    };

  # the one entry point: compose -> check -> select -> strip -> merge. merge is
  # supplied (a values -> value fold from merge.nix) so its strategy table and
  # conflict policy stay pluggable; checks default to the registered list but can
  # be extended by a caller without touching anything here. ctx is asserted after
  # compose because which entities a build needs depends on what the claims narrow
  # on, not on the registry as a whole -- so assertCtx reads the composed leaves.
  pipeline =
    {
      registry,
      merge,
      ctx,
      checks ? defaultChecks,
    }:
    unit:
    let
      leaves = compose registry unit;
      checkObservation = observeCheck checks registry leaves;
      checked = checkObservation.value;
      ctxObservation = observeCtx registry ctx checked;
      ctx' = ctxObservation.value;
      selection = observeSelect registry ctx' checked;
    in
    {
      value = merge (strip selection.selected);
      trace = builtins.genList (
        i:
        (builtins.elemAt selection.trace i)
        // {
          checkResults = builtins.elemAt checkObservation.trace i;
          ctxRequirements = builtins.elemAt ctxObservation.trace i;
        }
      ) (length selection.trace);
    };

  resolve = args: unit: (pipeline args unit).value;
  trace = pipeline;
in
{
  inherit
    compose
    strip
    resolve
    trace
    satisfiableCheck
    defaultChecks
    topClaim
    identifyUnit
    # exported so a golden-error test can assert its exact output against
    # crafted diagnostics while trace identity uses the same helper.
    renderDiags
    ;
  check = runCheck;
  select = runSelect;
}
