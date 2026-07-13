# _lib/ownerships/surface.nix
#
# The surface aspects author against. Its only job is to erase the ceremony the
# old scoped path needed -- instead of `{ host, user }: let for = scoped.for ...`
# an aspect hands `resolve` a plain list of self-labeling units, and the build
# context is read in here, not by the author. A unit carries its owners as
# ordinary keys (hosts / users / exceptHosts / exceptUsers / when); whatever's
# left is its config. Untagged means globally owned. This is a thin translator
# onto the engine's claim tree and holds no resolution logic of its own, so every
# nesting and conflict guarantee still comes from the engine.
{
  lib,
  descriptors ? null,
}:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  axisDescriptors = if descriptors == null then axes.descriptors else descriptors;
  resolveLib = import ./resolve.nix {
    inherit lib;
    descriptors = axisDescriptors;
  };
  mergeLib = import ./merge.nix { inherit lib; };

  defaultMerge = (mergeLib.mkMerge { }).mergeTracked;

  # Descriptor key order is stable because it also controls which malformed key
  # an author sees first when several are wrong.
  claimKeys = axes.claimKeysFor axisDescriptors;
  # label/source are reserved the same way `value`/`children` are: optional
  # plain-string identification for diagnostics, never config, never merged --
  # they ride the leaf as siblings of `value`, and `strip` only ever pulls
  # `.value`, so they're dropped before merge with no extra work.
  reserved = claimKeys ++ [
    "children"
    "value"
    "label"
    "source"
  ];

  # ownership keys are read by name off a unit's top level, so a config value
  # sitting on a reserved key would be silently swallowed as a claim. the one
  # realistic collision is a NixOS `users` attrset landing where the `users`
  # name-list belongs, so shape-check the claim keys and fail at author time
  # rather than resolve something the author never meant.
  checkShape =
    unit:
    let
      checkedClaims = axes.validateUnit axisDescriptors unit;
      badLabel = unit ? label && !builtins.isString unit.label;
      badSource = unit ? source && !builtins.isString unit.source;
      # a value block routes unambiguously only when it's the sole non-reserved
      # content on the unit -- claims and children still narrow around it
      # exactly as they do around inline config, so only a genuine leftover
      # inline key next to `value` is the ambiguous case.
      leftover = removeAttrs unit reserved;
      badMixed = unit ? value && leftover != { };
    in
    builtins.seq checkedClaims (
      if badLabel then
        throw "ownerships: 'label' must be a plain string; got ${builtins.typeOf unit.label}"
      else if badSource then
        throw "ownerships: 'source' must be a plain string; got ${builtins.typeOf unit.source}"
      else if badMixed then
        throw "ownerships: a unit cannot mix a 'value' block with inline config keys (${lib.concatStringsSep ", " (builtins.attrNames leftover)}) -- route everything through 'value' or drop it"
      else
        unit
    );

  claimOf = axes.claimOf axisDescriptors;

  # the payload riding this leaf: the escape-hatch block verbatim when the unit
  # used one, otherwise whatever's left after stripping the reserved keys --
  # same rule as before the hatch existed. two different `value`s share the
  # word, not the meaning: `checked.value` is the author-facing escape-hatch
  # key, `payload` becomes the engine leaf's `value` field (the config every
  # leaf carries, hatch or not) -- don't conflate them.
  translate =
    unit:
    let
      checked = checkShape unit;
      payload = checked.value or (removeAttrs checked reserved);
    in
    {
      claim = claimOf checked;
    }
    // lib.optionalAttrs (payload != { }) { value = payload; }
    // lib.optionalAttrs (checked ? children) { children = map translate checked.children; }
    // lib.optionalAttrs (checked ? label) { inherit (checked) label; }
    // lib.optionalAttrs (checked ? source) { inherit (checked) source; };

  # bind the surface to a roster once -- the fleet the owners are checked against.
  # the returned resolve takes the authored units and yields a context-consuming
  # function; den fills host/user, so the aspect never destructures them. the
  # engine args -- registry (host, user, and the shared `when` predicate axis)
  # and the membership check -- all come from resolve.nix's engineArgsFor, so
  # nothing here is surface-local anymore. `resolve` is a name at three layers --
  # this public one an aspect calls, resolve.nix's `resolveWith`, and the
  # engine's own `resolve` invoked below; only this one is meant for aspects.
  mkResolve =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units: rawCtx:
    engine.resolve {
      inherit (base) registry stages;
      merge = defaultMerge;
      ctx = axes.contextFor base.registry rawCtx;
    } { children = map translate units; };

  # Trace siblings use the same translated tree and engine pipeline as their
  # value-only counterparts. They are exported for manual inspection and tests;
  # ordinary aspect bindings keep their existing return type.
  mkResolveTrace =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units: rawCtx:
    engine.trace {
      inherit (base) registry stages;
      merge = defaultMerge;
      ctx = axes.contextFor base.registry rawCtx;
    } { children = map translate units; };

  # a system-scope resolve binds a host but no user (ctx.user = null), so a
  # `users` / `exceptUsers` claim anywhere in the tree can never own anything --
  # a host-wide slice has no user to narrow to. reject that when the units are
  # handed in, before resolve runs, naming the offending key and its value. the
  # engine's resolve-time missing-ctx throw still backstops a miss here, so this
  # is a clearer, earlier message rather than the only line of defense.
  assertScope =
    scope: unit:
    let
      forbidden = axes.forbiddenKeysFor axisDescriptors scope;
      offending = builtins.filter (key: unit ? ${key.name}) forbidden;
      bad = if offending == [ ] then null else builtins.head offending;
    in
    if bad != null then
      throw (bad.scopeError scope bad.name unit.${bad.name})
    else
      lib.all (assertScope scope) (unit.children or [ ]);

  # host-only sibling of mkResolve: same roster-bound registry + stages, but the
  # ctx carries only a host (user = null). the retained user axis stays global on
  # every unit here -- the guard above forbids narrowing it -- so assertCtx never
  # demands a user entity and the membership check (which reads claims and
  # roster, never ctx) degrades to host-only on its own. mkResolve is left
  # untouched, so every already-migrated user-scope aspect resolves identically.
  mkResolveSystem =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units: rawCtx:
    builtins.seq (lib.all (assertScope "system") units) (
      engine.resolve {
        inherit (base) registry stages;
        merge = defaultMerge;
        ctx = axes.contextFor base.registry rawCtx;
      } { children = map translate units; }
    );

  mkResolveSystemTrace =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units: rawCtx:
    builtins.seq (lib.all (assertScope "system") units) (
      engine.trace {
        inherit (base) registry stages;
        merge = defaultMerge;
        ctx = axes.contextFor base.registry rawCtx;
      } { children = map translate units; }
    );

  # Opt-in strict siblings of mkResolve/mkResolveSystem: validate the ctx's
  # roster-backed context names before delegating to the exact same
  # resolve function, so the permissive path is byte-identical by
  # construction rather than kept in sync by hand. Mode is a separate
  # function, not a flag -- the same precedent mkResolveSystem already set
  # against mkResolve.
  mkResolveStrict =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
      resolveFn = mkResolve roster;
    in
    units: rawCtx:
    let
      ctx = axes.contextFor base.registry rawCtx;
    in
    builtins.seq (resolveLib.validateRosterCtx roster ctx) (resolveFn units rawCtx);

  # The descriptor projection fills unavailable entity keys with null, so strict
  # system validation checks the host while every forbidden axis stays global.
  mkResolveSystemStrict =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
      resolveFn = mkResolveSystem roster;
    in
    units: rawCtx:
    let
      ctx = axes.contextFor base.registry rawCtx;
    in
    builtins.seq (resolveLib.validateRosterCtx roster ctx) (resolveFn units rawCtx);
in
{
  inherit
    mkResolve
    mkResolveSystem
    mkResolveTrace
    mkResolveSystemTrace
    mkResolveStrict
    mkResolveSystemStrict
    translate
    claimKeys
    ;
  inherit (resolveLib) define toRoster mkRoster;
}
