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
{ lib }:
let
  engine = import ./engine.nix { inherit lib; };
  axes = import ./axes.nix { inherit lib; };
  resolveLib = import ./resolve.nix { inherit lib; };
  mergeLib = import ./merge.nix { inherit lib; };

  inherit (axes) include exclude;

  defaultMerge = (mergeLib.mkMerge { }).mergeAll;

  # keys that mean ownership rather than config. everything else on a unit is
  # its value; children nests. the tradeoff: a unit can't also carry a config
  # value whose first path segment is one of these words. in practice that's
  # only `users.*` (NixOS user management); the others never name a real option
  # path. a unit that needs to own a reserved-colliding path routes its config
  # through `value = { ... }` instead (see translate below) -- claims still
  # narrow around a value block exactly as they do around inline config.
  # `value` is reserved too, so routing is a static lexical check on the
  # unit's own keys, never a shape guess.
  claimKeys = [
    "hosts"
    "users"
    "exceptHosts"
    "exceptUsers"
    "when"
  ];
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
  isNameList = v: builtins.isList v && lib.all builtins.isString v;
  checkShape =
    unit:
    let
      badList = builtins.filter (k: unit ? ${k} && !isNameList unit.${k}) [
        "hosts"
        "users"
        "exceptHosts"
        "exceptUsers"
      ];
      badWhen = unit ? when && !builtins.isFunction unit.when;
      badLabel = unit ? label && !builtins.isString unit.label;
      badSource = unit ? source && !builtins.isString unit.source;
      # a value block routes unambiguously only when it's the sole non-reserved
      # content on the unit -- claims and children still narrow around it
      # exactly as they do around inline config, so only a genuine leftover
      # inline key next to `value` is the ambiguous case.
      leftover = removeAttrs unit reserved;
      badMixed = unit ? value && leftover != { };
    in
    if badList != [ ] then
      throw "ownerships: '${builtins.head badList}' must be a list of names; got ${
        builtins.typeOf unit.${builtins.head badList}
      }. a reserved ownership key can't also be a config path on the same unit."
    else if badWhen then
      throw "ownerships: 'when' must be a predicate function of the build context"
    else if badLabel then
      throw "ownerships: 'label' must be a plain string; got ${builtins.typeOf unit.label}"
    else if badSource then
      throw "ownerships: 'source' must be a plain string; got ${builtins.typeOf unit.source}"
    else if badMixed then
      throw "ownerships: a unit cannot mix a 'value' block with inline config keys (${lib.concatStringsSep ", " (builtins.attrNames leftover)}) -- route everything through 'value' or drop it"
    else
      unit;

  # one axis' claim from its include/exclude key pair. naming both a set and its
  # complement on the same axis is rejected here instead of silently picking one,
  # and it costs no expressiveness: "own by A except B" is written by nesting an
  # exceptHosts child under a hosts parent, which the engine's polarity meet
  # resolves to include(A minus B). an axis the unit doesn't tag returns null and
  # is left off the claim, so the engine fills it with that axis' identity (global).
  polarityFor =
    unit: positive: negative:
    if unit ? ${positive} && unit ? ${negative} then
      throw "ownerships: a unit cannot set both '${positive}' and '${negative}' -- pick the set or its complement"
    else if unit ? ${positive} then
      include unit.${positive}
    else if unit ? ${negative} then
      exclude unit.${negative}
    else
      null;

  claimOf =
    unit:
    let
      host = polarityFor unit "hosts" "exceptHosts";
      user = polarityFor unit "users" "exceptUsers";
    in
    lib.optionalAttrs (host != null) { inherit host; }
    // lib.optionalAttrs (user != null) { inherit user; }
    // lib.optionalAttrs (unit ? when) { inherit (unit) when; };

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
    units:
    {
      host,
      user,
      ...
    }:
    engine.resolve {
      inherit (base) registry stages;
      merge = defaultMerge;
      ctx = {
        inherit host user;
      };
    } { children = map translate units; };

  # Trace siblings use the same translated tree and engine pipeline as their
  # value-only counterparts. They are exported for manual inspection and tests;
  # ordinary aspect bindings keep their existing return type.
  mkResolveTrace =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units:
    {
      host,
      user,
      ...
    }:
    engine.trace {
      inherit (base) registry stages;
      merge = defaultMerge;
      ctx = {
        inherit host user;
      };
    } { children = map translate units; };

  # a system-scope resolve binds a host but no user (ctx.user = null), so a
  # `users` / `exceptUsers` claim anywhere in the tree can never own anything --
  # a host-wide slice has no user to narrow to. reject that when the units are
  # handed in, before resolve runs, naming the offending key and its value. the
  # engine's resolve-time missing-ctx throw still backstops a miss here, so this
  # is a clearer, earlier message rather than the only line of defense.
  systemUserKeys = [
    "users"
    "exceptUsers"
  ];
  assertNoUserClaim =
    unit:
    let
      offending = builtins.filter (k: unit ? ${k}) systemUserKeys;
    in
    if offending != [ ] then
      throw "ownerships: a system-scope (host-only) unit sets '${builtins.head offending}' = ${
        lib.generators.toPretty { multiline = false; } unit.${builtins.head offending}
      } -- a host-only slice binds no user, so it cannot narrow on users. drop the user claim or resolve this unit at user scope."
    else
      lib.all assertNoUserClaim (unit.children or [ ]);

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
    units:
    {
      host,
      ...
    }:
    builtins.seq (lib.all assertNoUserClaim units) (
      engine.resolve {
        inherit (base) registry stages;
        merge = defaultMerge;
        ctx = {
          inherit host;
          user = null;
        };
      } { children = map translate units; }
    );

  mkResolveSystemTrace =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units:
    {
      host,
      ...
    }:
    builtins.seq (lib.all assertNoUserClaim units) (
      engine.trace {
        inherit (base) registry stages;
        merge = defaultMerge;
        ctx = {
          inherit host;
          user = null;
        };
      } { children = map translate units; }
    );

  # Opt-in strict siblings of mkResolve/mkResolveSystem: validate the ctx's
  # host/user names against the roster before delegating to the exact same
  # resolve function, so the permissive path is byte-identical by
  # construction rather than kept in sync by hand. Mode is a separate
  # function, not a flag -- the same precedent mkResolveSystem already set
  # against mkResolve.
  mkResolveStrict =
    roster:
    let
      resolveFn = mkResolve roster;
    in
    units: ctx:
    builtins.seq (resolveLib.validateRosterCtx roster { inherit (ctx) host user; }) (
      resolveFn units ctx
    );

  # host-only sibling: mkResolveSystem's ctx never carries a user, so the
  # validator is handed user = null directly rather than read off ctx --
  # validateRosterCtx's own null-user branch is what keeps this host-only.
  mkResolveSystemStrict =
    roster:
    let
      resolveFn = mkResolveSystem roster;
    in
    units: ctx:
    builtins.seq (resolveLib.validateRosterCtx roster {
      inherit (ctx) host;
      user = null;
    }) (resolveFn units ctx);
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
    ;
  inherit (resolveLib) define toRoster;
}
