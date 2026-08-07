# _lib/ownerships/surface.nix
#
# the surface aspects author against. its only job is to erase the ceremony the
# old scoped path needed -- instead of `{ host, user } - let for = scoped.for ...`
# an aspect hands `resolve` a plain list of self-labeling units, and the build
# context is read in here, not by the author. a unit carries its owners as
# ordinary keys (hosts / users / excepthosts / exceptusers / when); whatever's
# left is its config. untagged means globally owned. this is a thin translator
# onto the engine's claim tree and holds no resolution logic of its own, so every
# nesting and conflict guarantee still comes from the engine.
{
  lib,
  descriptors ? null,
  relations ? null,
}:
let
  engine = import ./engine.nix { inherit lib; };
  krisis = import ../krisis { inherit lib; };
  axes = import ./axes.nix { inherit lib; };

  unitProblem = krisis.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "ownerships";
  };

  failUnit =
    diagnostic:
    krisis.throwDiagnostics {
      diagnostics = [ diagnostic ];
      formatDiagnostic = krisis.renderPlain;
    };

  # a missing or non-string label is usually what the error is about, so it
  # can't name the unit.
  labelOf =
    unit:
    lib.optionalAttrs (builtins.isAttrs unit && unit ? label && builtins.isString unit.label) {
      primary.label = unit.label;
    };
  descriptorSet = axes.compileDescriptors (
    if descriptors == null then axes.descriptors else descriptors
  );
  axisDescriptors = descriptorSet.descriptors;
  relationRegistrations = if relations == null then axes.relations else relations;
  resolveLib = import ./resolve.nix {
    inherit lib;
    descriptors = axisDescriptors;
    relations = relationRegistrations;
  };
  mergeLib = import ./merge.nix { inherit lib; };
  matrixLib = import ./matrix.nix { inherit lib; };

  defaultMerge = (mergeLib.mkMerge { }).mergeTracked;

  # descriptor key order is stable because it also controls which malformed key
  # an author sees first when several are wrong.
  inherit (descriptorSet) claimKeys;
  # label/source are reserved like `value`/`children`, optional
  # plain-string identification for diagnostics, never config, never merged --
  # they ride the leaf as siblings of `value`, and `strip` only ever pulls
  # `.value`, so they're dropped before merge with no extra work.
  reserved = claimKeys ++ [
    "children"
    "value"
    "label"
    "source"
    "mergeProfile"
  ];

  # ownership keys are read by name off a unit's top level, so a config value
  # sitting on a reserved key would be silently swallowed as a claim. the one
  # realistic collision is a nixos `users` attrset landing where the `users`
  # name-list belongs, so shape-check the claim keys and fail at author time
  # rather than resolve something the author never meant.
  checkShape =
    unit:
    if !builtins.isAttrs unit then
      failUnit (unitProblem {
        code = "unit-shape";
        message = "a unit must be an attribute set; got ${builtins.typeOf unit}";
      })
    else
      let
        checkedClaims = axes.validateUnitWith descriptorSet.authorKeys unit;
        badChildren =
          unit ? children && (!builtins.isList unit.children || !lib.all builtins.isAttrs unit.children);
        badValue = unit ? value && !builtins.isAttrs unit.value;
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
        if badChildren then
          failUnit (
            unitProblem (
              {
                code = "unit-children";
                message = "'children' must be a list of unit attribute sets";
              }
              // labelOf unit
            )
          )
        else if badValue then
          failUnit (
            unitProblem (
              {
                code = "unit-value";
                message = "'value' must be an attribute set; got ${builtins.typeOf unit.value}";
              }
              // labelOf unit
            )
          )
        else if badLabel then
          failUnit (unitProblem {
            code = "unit-label";
            message = "'label' must be a plain string; got ${builtins.typeOf unit.label}";
          })
        else if badSource then
          failUnit (
            unitProblem (
              {
                code = "unit-source";
                message = "'source' must be a plain string; got ${builtins.typeOf unit.source}";
              }
              // labelOf unit
            )
          )
        else if badMixed then
          failUnit (
            unitProblem (
              {
                code = "unit-mixed-value";
                message = "a unit cannot mix a 'value' block with inline config keys (${lib.concatStringsSep ", " (builtins.attrNames leftover)}) -- route everything through 'value' or drop it";
              }
              // labelOf unit
            )
          )
        else
          unit
      );

  claimOf = axes.claimOf axisDescriptors;

  # the payload riding this leaf is the escape-hatch block verbatim when the unit
  # used one, otherwise whatever's left after stripping the reserved keys --
  # same rule as before the hatch existed. two different `value`s share the
  # word, not the meaning. `checked.value` is the author-facing escape-hatch
  # key, `payload` becomes the engine leaf's `value` field (the config every
  # leaf carries, hatch or not) -- don't conflate them.
  translateWith =
    profileNames: unit:
    let
      checked = checkShape unit;
      profileChecked =
        if profileNames == null || !(checked ? mergeProfile) then
          checked
        else if !builtins.isString checked.mergeProfile then
          failUnit (unitProblem {
            code = "unit-merge-profile";
            message = "'mergeProfile' must be a plain string; got ${builtins.typeOf checked.mergeProfile}";
          })
        else if !(builtins.elem checked.mergeProfile profileNames) then
          failUnit (
            unitProblem (
              {
                code = "unit-merge-profile-unknown";
                message = "unknown merge profile '${checked.mergeProfile}'";
              }
              // labelOf checked
            )
          )
        else
          checked;
      payload = profileChecked.value or (removeAttrs profileChecked reserved);
      unitIdentity = engine.identifyUnit {
        unit = profileChecked;
        label = profileChecked.label or null;
        source = profileChecked.source or null;
      };
      contextualProfile = builtins.foldl' (
        result: key:
        if result ? ${key} && builtins.isFunction result.${key} then
          result
          // {
            ${key} =
              ctx:
              krisis.withErrorContext "ownerships: while evaluating '${key}' predicate for ${unitIdentity}" (
                profileChecked.${key} ctx
              );
          }
        else
          result
      ) profileChecked claimKeys;
      claim = claimOf contextualProfile;
      children = map (translateWith profileNames) (profileChecked.children or [ ]);
      carriesDeclaration = lib.any (key: profileChecked ? ${key}) (
        claimKeys
        ++ [
          "value"
          "label"
          "source"
          "mergeProfile"
        ]
      );
      valid = builtins.deepSeq claim (
        if payload == { } && children == [ ] && carriesDeclaration then
          failUnit (unitProblem {
            code = "unit-metadata-only";
            message = "${unitIdentity} has ownership metadata but no config or children";
          })
        else
          true
      );
    in
    builtins.seq valid (
      {
        inherit claim;
      }
      // lib.optionalAttrs (payload != { }) { value = payload; }
      // lib.optionalAttrs (profileChecked ? children) { inherit children; }
      // lib.optionalAttrs (profileChecked ? label) { inherit (profileChecked) label; }
      // lib.optionalAttrs (profileChecked ? source) { inherit (profileChecked) source; }
      // lib.optionalAttrs (profileChecked ? mergeProfile) { inherit (profileChecked) mergeProfile; }
    );

  translate = translateWith null;

  # bind the surface to a roster once -- the fleet the owners are checked against.
  # the returned resolve takes the authored units and yields a context-consuming
  # function; den fills host/user, so the aspect never destructures them. the
  # engine args -- registry (host, user, and the shared `when` predicate axis)
  # plus registered relation stages -- all come from resolve.nix's engineargsfor, so
  # nothing here is surface-local anymore. `resolve` is a name at three layers --
  # this public one an aspect calls, resolve.nix's `resolvewith`, and the
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

  # trace siblings use the same translated tree and engine pipeline as their
  # value-only counterparts. they are exported for manual inspection and tests;
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
  # `users` / `exceptusers` claim anywhere in the tree can never own anything --
  # a host-wide slice has no user to narrow to. reject that when the units are
  # handed in, before resolve runs, naming the offending key and its value. the
  # engine's resolve-time missing-ctx throw still backstops a miss here, so this
  # is a clearer, earlier message rather than the only line of defense.
  forbiddenByScope = lib.genAttrs [
    "user"
    "system"
  ] (axes.forbiddenKeysFor axisDescriptors);

  assertScope =
    scope: unit:
    let
      forbidden = forbiddenByScope.${scope};
      offending = builtins.filter (key: unit ? ${key.name}) forbidden;
      bad = if offending == [ ] then null else builtins.head offending;
    in
    if bad != null then
      throw (bad.scopeError scope bad.name unit.${bad.name})
    else
      lib.all (assertScope scope) (unit.children or [ ]);

  # host-only sibling of mkresolve uses the same roster-bound registry and stages, but the
  # ctx carries only a host (user = null). the retained user axis stays global on
  # every unit here -- the guard above forbids narrowing it -- so assertctx never
  # demands a user entity and the membership check (which reads claims and
  # roster, never ctx) degrades to host-only on its own. mkresolve is left
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

  # prepared resolve splits the pipeline at its context boundary: the units are
  # translated and composed once when they are handed in, and the returned
  # function runs only the per-ctx tail (ctx demand, select, survivors, merge)
  # for each context given to it. callers that resolve the same unit set for
  # many contexts -- program aspects instantiated once per user -- hoist every
  # ctx-independent phase.
  mkResolvePrepared =
    roster:
    let
      base = resolveLib.engineArgsFor roster;
    in
    units:
    let
      prepared = engine.prepare {
        inherit (base) registry stages;
        merge = defaultMerge;
      } { children = map translate units; };
    in
    rawCtx: (engine.applyPrepared prepared (axes.contextFor base.registry rawCtx)).value;

  # matrix siblings keep config values inside the engine and return only stable
  # snapshot keys, human identity, shallow shape, and selection metadata. a
  # caller can enrich each roster context for predicates that read more than
  # entity names; the default is the smallest concrete context.
  mkResolveMatrix =
    roster:
    {
      units,
      # hostname is the canonical host id; bind it as host.id so the generic
      # memberof reads it directly instead of re-deriving (and double-prefixing)
      # a system from a bare name.
      contextFor ? (
        { hostName, userName }: {
          host.id = hostName;
          user.name = userName;
        }
      ),
    }:
    let
      base = resolveLib.engineArgsFor roster;
      contexts = matrixLib.mkUserContexts {
        inherit roster;
        contextFor = names: axes.contextFor base.registry (contextFor names);
      };
    in
    matrixLib.report {
      inherit roster contexts;
      inherit (base) registry stages;
      scope = "user";
      unit.children = map translate units;
    };

  mkResolveSystemMatrix =
    roster:
    {
      units,
      contextFor ? ({ hostName }: { host.id = hostName; }),
    }:
    let
      base = resolveLib.engineArgsFor roster;
      contexts = matrixLib.mkSystemContexts {
        inherit roster;
        contextFor = names: axes.contextFor base.registry (contextFor names);
      };
    in
    builtins.seq (lib.all (assertScope "system") units) (
      matrixLib.report {
        inherit roster contexts;
        inherit (base) registry stages;
        scope = "system";
        unit.children = map translate units;
      }
    );

  mkResolveProfiled =
    profileArgs: roster:
    let
      base = resolveLib.engineArgsFor roster;
      profiles = profileArgs.profiles or mergeLib.builtinProfiles;
      profiledMerge = (mergeLib.mkMerge (profileArgs // { inherit profiles; })).mergeTracked;
      translateProfiled = translateWith (builtins.attrNames profiles);
    in
    units: rawCtx:
    engine.resolve {
      inherit (base) registry stages;
      merge = profiledMerge;
      ctx = axes.contextFor base.registry rawCtx;
    } { children = map translateProfiled units; };

  mkResolveSystemProfiled =
    profileArgs: roster:
    let
      base = resolveLib.engineArgsFor roster;
      profiles = profileArgs.profiles or mergeLib.builtinProfiles;
      profiledMerge = (mergeLib.mkMerge (profileArgs // { inherit profiles; })).mergeTracked;
      translateProfiled = translateWith (builtins.attrNames profiles);
    in
    units: rawCtx:
    builtins.seq (lib.all (assertScope "system") units) (
      engine.resolve {
        inherit (base) registry stages;
        merge = profiledMerge;
        ctx = axes.contextFor base.registry rawCtx;
      } { children = map translateProfiled units; }
    );

  # opt-in strict siblings validate the ctx's
  # roster-backed context names before delegating to the exact same
  # resolve function, so the permissive path is byte-identical by
  # construction rather than kept in sync by hand. mode is a separate
  # function, not a flag -- the same precedent mkresolvesystem already set
  # against mkresolve.
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

  # the descriptor projection fills unavailable entity keys with null, so strict
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
    mkResolvePrepared
    mkResolveMatrix
    mkResolveSystemMatrix
    mkResolveStrict
    mkResolveSystemStrict
    mkResolveProfiled
    mkResolveSystemProfiled
    translate
    claimKeys
    ;
  inherit (resolveLib) define toRoster mkRoster;
}
