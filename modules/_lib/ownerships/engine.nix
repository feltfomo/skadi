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

  # run every sub-check over every leaf; any diagnostic is a hard error. checks
  # are a LIST, so a new invariant (coverage assertions, etc.) is a new entry --
  # never a branch in here. returns the leaves untouched when clean.
  runCheck =
    subChecks: registry: leaves:
    let
      diags = concatMap (leaf: concatMap (c: c registry leaf) subChecks) leaves;
    in
    if diags == [ ] then leaves else throw (renderDiags diags);

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
  runSelect =
    registry: ctx: leaves:
    filter (
      leaf:
      all (
        name:
        let
          axis = registry.${name};
        in
        axis.isTop leaf.claim.${name} || axis.select leaf.claim.${name} ctx
      ) (attrNames registry)
    ) leaves;

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
  assertCtx =
    registry: ctx: leaves:
    let
      ctxAxes = filter (name: registry.${name}.ctxKey != null) (attrNames registry);
      narrowsOn = name: leaf: !(registry.${name}.isTop leaf.claim.${name});
      entityMissing =
        name:
        let
          key = registry.${name}.ctxKey;
        in
        !(ctx ? ${key}) || ctx.${key} == null;
      # one diagnostic per (leaf, axis) where a leaf narrows on a ctx-reading
      # axis whose entity this build ctx doesn't provide. it carries the
      # offending unit and its claims and renders the narrowing claim value, so an
      # author can trace the miss back to the exact spec -- the same { kind; unit;
      # axis; claims; reason } shape satisfiableCheck emits, through the same
      # renderer for one consistent structured error.
      diags = concatMap (
        leaf:
        concatMap (
          name:
          lib.optional (narrowsOn name leaf && entityMissing name) {
            kind = "missing-ctx";
            unit = leaf.value;
            label = leaf.label or null;
            source = leaf.source or null;
            axis = name;
            claims = leaf.claim;
            reason = "axis '${name}' is narrowed on by claim ${
              lib.generators.toPretty { multiline = false; } leaf.claim.${name}
            } but the build ctx provides no entity for key '${registry.${name}.ctxKey}' -- only untagged (global) claims resolve without a build context";
          }
        ) ctxAxes
      ) leaves;
    in
    if diags == [ ] then ctx else throw (renderDiags diags);

  # the one entry point: compose -> check -> select -> strip -> merge. merge is
  # supplied (a values -> value fold from merge.nix) so its strategy table and
  # conflict policy stay pluggable; checks default to the registered list but can
  # be extended by a caller without touching anything here. ctx is asserted after
  # compose because which entities a build needs depends on what the claims narrow
  # on, not on the registry as a whole -- so assertCtx reads the composed leaves.
  resolve =
    {
      registry,
      merge,
      ctx,
      checks ? defaultChecks,
    }:
    unit:
    let
      leaves = compose registry unit;
      checked = runCheck checks registry leaves;
      ctx' = assertCtx registry ctx checked;
      selected = runSelect registry ctx' checked;
    in
    merge (strip selected);
in
{
  inherit
    compose
    strip
    resolve
    satisfiableCheck
    defaultChecks
    topClaim
    # exported so a golden-error test can assert its exact output against
    # crafted diagnostics -- renderDiag/identifyUnit stay internal, since
    # renderDiags is the one entry point an author-facing message actually
    # goes through.
    renderDiags
    ;
  check = runCheck;
  select = runSelect;
}
