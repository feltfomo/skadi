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
  # each carrying its effective claim. nesting is `children`; a child narrows its
  # parent. nodes without a value contribute only their claim to descendants.
  compose =
    registry: unit:
    let
      go =
        parent: node:
        let
          eff = narrowClaim registry parent (node.claim or { });
          self = lib.optional (node ? value) {
            claim = eff;
            inherit (node) value;
          };
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

  renderDiags =
    diags:
    "ownerships: ${toString (length diags)} ownership error(s):\n"
    + lib.concatMapStringsSep "\n" (d: "  - ${d.reason}") diags;

  # keep the leaves this build's ctx falls under on every axis; dropped leaves are
  # inactive -- silent, not an error. runs AFTER check, so an impossible leaf
  # errors for everyone regardless of who is building, while a satisfiable leaf
  # that just doesn't match this build falls away quietly.
  runSelect =
    registry: ctx: leaves:
    filter (
      leaf: all (name: registry.${name}.select leaf.claim.${name} ctx) (attrNames registry)
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
        axis = name;
        claims = leaf.claim;
        reason = "axis '${name}' claim can never be satisfied (disjoint nest or unknown name)";
      }
    ) (attrNames registry);

  defaultChecks = [ satisfiableCheck ];

  # the build ctx must carry an entity for every axis that declares a ctxKey; an
  # axis with ctxKey = null (a predicate axis, which has no entity of its own)
  # needs nothing here. reads axis.ctxKey off each registered axis rather than
  # the registry's own attr names, so the engine still never hardcodes host,
  # user, or when.
  assertCtx =
    registry: ctx:
    let
      needed = filter (axis: axis.ctxKey != null) (lib.attrValues registry);
      missing = filter (axis: !(ctx ? ${axis.ctxKey})) needed;
    in
    if missing == [ ] then
      ctx
    else
      throw "ownerships: build ctx is missing an entity for key(s): ${
        lib.concatStringsSep ", " (map (axis: axis.ctxKey) missing)
      }";

  # the one entry point: compose -> check -> select -> strip -> merge. merge is
  # supplied (a values -> value fold from merge.nix) so its strategy table and
  # conflict policy stay pluggable; checks default to the registered list but can
  # be extended by a caller without touching anything here.
  resolve =
    {
      registry,
      merge,
      ctx,
      checks ? defaultChecks,
    }:
    unit:
    let
      ctx' = assertCtx registry ctx;
      leaves = compose registry unit;
      selected = runSelect registry ctx' (runCheck checks registry leaves);
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
    ;
  check = runCheck;
  select = runSelect;
}
