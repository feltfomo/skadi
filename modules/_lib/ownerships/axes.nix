# _lib/ownerships/axes.nix
#
# Axis implementations, authoring descriptors, and cross-axis relation data.
# The engine consumes registries built from these records; it never learns axis
# names, author keys, roster fields, or which scopes may use them. New axes and
# relations extend data here instead of branching the translator or resolver.
{ lib }:
let
  inherit (builtins) elem filter;

  mk = tag: set: { inherit tag set; };
  include = mk "include";
  exclude = mk "exclude";
  global = exclude [ ];
  isGlobal = v: v.tag == "exclude" && v.set == [ ];

  inter = a: b: filter (x: elem x b) a;
  diff = a: b: filter (x: !(elem x b)) a;
  union = a: b: a ++ filter (x: !(elem x a)) b;

  meet =
    a: b:
    if a.tag == "include" && b.tag == "include" then
      include (inter a.set b.set)
    else if a.tag == "exclude" && b.tag == "exclude" then
      exclude (union a.set b.set)
    else
      let
        inc = if a.tag == "include" then a else b;
        exc = if a.tag == "include" then b else a;
      in
      include (diff inc.set exc.set);

  resolveMembers = members: v: if v.tag == "include" then inter v.set members else diff members v.set;

  # Shared alias/canonical resolution, used by every set axis and by the
  # registered alias-validation stage. A claim name that is already a canonical
  # member is kept as-is; otherwise it expands through the roster-provided alias
  # map (default {} = identity). An unknown name stays itself and falls through
  # to the existing unknown-name/disjoint diagnostic.
  canonicalizeName =
    aliasMap: members: name:
    if elem name members then [ name ] else aliasMap.${name} or [ name ];

  canonicalizeSet =
    aliasMap: members: set:
    lib.unique (builtins.concatMap (canonicalizeName aliasMap members) set);

  # Bare aliases that resolve to more than one canonical member. A bare claim
  # never fans out silently; the registered alias-validation stage fails loud on
  # these before satisfiability or relations run.
  ambiguousNames =
    aliasMap: members: set:
    filter (name: !(elem name members) && builtins.length (aliasMap.${name} or [ ]) > 1) set;

  mkSetAxis =
    {
      key,
      members ? [ ],
      aliasMap ? { },
      memberOf ? (entity: entity.name),
    }:
    let
      canonicalValue = v: v // { set = canonicalizeSet aliasMap members v.set; };
      observe =
        v:
        let
          materializedMembers = resolveMembers members (canonicalValue v);
        in
        {
          inherit materializedMembers;
          satisfiable = materializedMembers != [ ];
          select =
            ctx:
            let
              selected = elem (memberOf ctx.${key}) materializedMembers;
            in
            {
              inherit selected;
              decision = if selected then "selected" else "rejected";
            };
        };
    in
    {
      top = global;
      narrow = meet;
      inherit observe;
      satisfiable = v: (observe v).satisfiable;
      select = v: ctx: ((observe v).select ctx).selected;
      isTop = isGlobal;
      ctxKey = key;
      ambiguous = v: ambiguousNames aliasMap members v.set;
    };

  predicateAxis =
    let
      observe = pred: {
        satisfiable = true;
        select =
          ctx:
          let
            selected = pred ctx;
          in
          {
            inherit selected;
            decision = if selected then "selected" else "rejected";
          };
      };
    in
    {
      top = _: true;
      narrow = a: b: (ctx: a ctx && b ctx);
      inherit observe;
      satisfiable = pred: (observe pred).satisfiable;
      select = pred: ctx: ((observe pred).select ctx).selected;
      isTop = _: false;
      ctxKey = null;
      ambiguous = _pred: [ ];
    };

  isNameList = v: builtins.isList v && lib.all builtins.isString v;

  nameListKey = name: order: {
    inherit name order;
    valid = isNameList;
    shapeError =
      value:
      "ownerships: '${name}' must be a list of names; got ${builtins.typeOf value}. a reserved ownership key can't also be a config path on the same unit.";
  };

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

  defaultScopeError =
    scope: key: value:
    "ownerships: a ${scope}-scope unit sets '${key}' = ${
      lib.generators.toPretty { multiline = false; } value
    } -- this ownership axis is unavailable in ${scope} scope";

  mkSetDescriptor =
    {
      name,
      includeKey,
      excludeKey,
      includeOrder,
      excludeOrder,
      allowedScopes,
      roster,
      leafStages ? (_roster: [ ]),
      scopeError ? defaultScopeError,
    }:
    {
      inherit
        name
        allowedScopes
        roster
        leafStages
        scopeError
        ;
      authorKeys = [
        (nameListKey includeKey includeOrder)
        (nameListKey excludeKey excludeOrder)
      ];
      parse =
        unit:
        let
          value = polarityFor unit includeKey excludeKey;
        in
        lib.optionalAttrs (value != null) { ${name} = value; };
      axisFor =
        rosterValue:
        mkSetAxis {
          key = name;
          members = rosterValue.${roster.membersField};
          aliasMap = (rosterValue.aliases or { }).${name} or { };
          memberOf = roster.memberOf or (entity: entity.name);
        };
      ctxClaim =
        ctx:
        if ctx ? ${name} && ctx.${name} != null then
          { ${name} = include [ ((roster.memberOf or (entity: entity.name)) ctx.${name}) ]; }
        else
          { };
      ctxLabel =
        ctx: if ctx ? ${name} && ctx.${name} != null then "${name} '${ctx.${name}.name}'" else null;
    };

  mkPredicateDescriptor =
    {
      name,
      authorKey,
      order,
      allowedScopes,
    }:
    {
      inherit name allowedScopes;
      roster = null;
      leafStages = _roster: [ ];
      scopeError = defaultScopeError;
      authorKeys = [
        {
          name = authorKey;
          inherit order;
          valid = builtins.isFunction;
          shapeError = _value: "ownerships: '${authorKey}' must be a predicate function of the build context";
        }
      ];
      parse = unit: lib.optionalAttrs (unit ? ${authorKey}) { ${name} = unit.${authorKey}; };
      axisFor = _roster: predicateAxis;
      ctxClaim = _ctx: { };
      ctxLabel = _ctx: null;
    };

  hostUserRelation = {
    name = "host-user-membership";
    leftAxis = "host";
    rightAxis = "user";
    unknownFor = roster: {
      left = [ ];
      right = roster.usersWithUnknownMembership;
    };
    compatibleFor =
      roster: host: user:
      elem user (roster.membership.${host} or [ ]);
    reason =
      hosts: users:
      "no user in { ${builtins.concatStringsSep ", " users} } lives on any host in { ${builtins.concatStringsSep ", " hosts} } -- this host/user co-ownership can never apply";
  };

  # Canonical host identity is "<system>/<name>"; a bare name is an alias. A
  # one-arg `define.host "khion"` stays a standalone declaration (system
  # "standalone", bare-name alias) so existing callers keep byte-identical
  # resolve/config output; the optional attrs form federates a host onto a real
  # system and can carry extra aliases and dimension data.
  canonicalHostId = system: name: "${system}/${name}";

  aliasesFor =
    entries:
    lib.foldl' (
      aliases: entry:
      lib.foldl' (
        result: alias:
        result
        // {
          ${alias} = lib.unique ((result.${alias} or [ ]) ++ [ entry.id ]);
        }
      ) aliases entry.aliases
    ) { } entries;

  hostRoster = {
    membersField = "hosts";
    # A host ctx entity resolves to its canonical id: an explicit id wins,
    # otherwise it is derived from the entity's own system/name. A caller adds
    # host.system additively; a bare standalone ctx defaults the system.
    memberOf = entity: entity.id or (canonicalHostId (entity.system or "standalone") entity.name);
    define =
      let
        mk =
          name:
          {
            system ? "standalone",
            dimensions ? { },
            aliases ? [ name ],
          }:
          {
            kind = "host";
            inherit
              name
              system
              dimensions
              aliases
              ;
            id = canonicalHostId system name;
          };
      in
      name: (mk name { }) // { __functor = _self: attrs: mk name attrs; };
    project =
      { declarations, ... }:
      let
        hostDecls = builtins.filter (d: d.kind == "host") declarations;
        dimensionNames = lib.unique (builtins.concatMap (h: builtins.attrNames h.dimensions) hostDecls);
        withDim = dim: builtins.filter (h: h.dimensions ? ${dim}) hostDecls;
      in
      {
        hosts = lib.unique (map (h: h.id) hostDecls);
        aliases = {
          host = aliasesFor hostDecls;
        };
        display = {
          host = builtins.listToAttrs (
            map (h: {
              name = h.id;
              value = h.name;
            }) hostDecls
          );
        };
        dimensions = builtins.listToAttrs (
          map (dim: {
            name = dim;
            value = {
              members = lib.unique (map (h: h.dimensions.${dim}) (withDim dim));
              byHost = builtins.listToAttrs (
                map (h: {
                  name = h.id;
                  value = h.dimensions.${dim};
                }) (withDim dim)
              );
            };
          }) dimensionNames
        );
      };
  };

  userRoster = {
    membersField = "users";
    memberOf = entity: entity.id or entity.name;
    define =
      name:
      {
        hosts ? null,
        id ? name,
        aliases ? [ name ],
      }:
      {
        kind = "user";
        inherit
          name
          hosts
          id
          aliases
          ;
      };
    project =
      { declarations, roster }:
      let
        users = builtins.filter (d: d.kind == "user") declarations;
        # a user's declared hosts may be bare aliases or canonical ids. explicit
        # unknown and ambiguous references fail while the roster is constructed.
        resolveHost =
          name:
          if builtins.elem name roster.hosts then
            [ name ]
          else
            let
              matches = roster.aliases.host.${name} or [ ];
            in
            if matches == [ ] then
              throw "ownerships: user roster references unknown host '${name}'"
            else if builtins.length matches > 1 then
              throw "ownerships: user roster host alias '${name}' is ambiguous; use a canonical system/name"
            else
              matches;
        canonHosts = u: if u.hosts == null then null else builtins.concatMap resolveHost u.hosts;
        usersOn =
          h:
          lib.unique (
            map (u: u.id) (
              builtins.filter (
                u:
                let
                  ch = canonHosts u;
                in
                ch != null && builtins.elem h ch
              ) users
            )
          );
      in
      {
        users = lib.unique (map (u: u.id) users);
        aliases = (roster.aliases or { }) // {
          user = aliasesFor users;
        };
        membership = lib.genAttrs roster.hosts usersOn;
        usersWithUnknownMembership = lib.unique (
          map (u: u.id) (builtins.filter (u: u.hosts == null) users)
        );
        display = (roster.display or { }) // {
          user = builtins.listToAttrs (
            map (u: {
              name = u.id;
              value = u.name;
            }) users
          );
        };
      };
  };

  userScopeError =
    scope: key: value:
    if scope == "system" then
      "ownerships: a system-scope (host-only) unit sets '${key}' = ${
        lib.generators.toPretty { multiline = false; } value
      } -- a host-only slice binds no user, so it cannot narrow on users. drop the user claim or resolve this unit at user scope."
    else
      defaultScopeError scope key value;

  descriptors = [
    (mkSetDescriptor {
      name = "host";
      includeKey = "hosts";
      excludeKey = "exceptHosts";
      includeOrder = 10;
      excludeOrder = 30;
      allowedScopes = [
        "user"
        "system"
      ];
      roster = hostRoster;
    })
    (mkSetDescriptor {
      name = "user";
      includeKey = "users";
      excludeKey = "exceptUsers";
      includeOrder = 20;
      excludeOrder = 40;
      allowedScopes = [ "user" ];
      roster = userRoster;
      scopeError = userScopeError;
    })
    (mkPredicateDescriptor {
      name = "when";
      authorKey = "when";
      order = 50;
      allowedScopes = [
        "user"
        "system"
      ];
    })
  ];

  relations = [ hostUserRelation ];

  authorKeysFor =
    axisDescriptors:
    builtins.sort (a: b: a.order < b.order) (
      builtins.concatMap (descriptor: descriptor.authorKeys) axisDescriptors
    );

  claimKeysFor = axisDescriptors: map (key: key.name) (authorKeysFor axisDescriptors);

  validateUnit =
    axisDescriptors: unit:
    let
      invalid = builtins.filter (key: unit ? ${key.name} && !key.valid unit.${key.name}) (
        authorKeysFor axisDescriptors
      );
      bad = if invalid == [ ] then null else builtins.head invalid;
    in
    if bad == null then unit else throw (bad.shapeError unit.${bad.name});

  claimOf =
    axisDescriptors: unit:
    lib.foldl' (claim: descriptor: claim // descriptor.parse unit) { } axisDescriptors;

  registryFor =
    axisDescriptors: roster:
    builtins.listToAttrs (
      map (descriptor: {
        inherit (descriptor) name;
        value = descriptor.axisFor roster;
      }) axisDescriptors
    );

  relationsFor =
    relationRegistrations: roster:
    map (
      relation:
      (removeAttrs relation [
        "unknownFor"
        "compatibleFor"
      ])
      // {
        unknown = relation.unknownFor roster;
        compatible = relation.compatibleFor roster;
      }
    ) relationRegistrations;

  leafStagesFor =
    axisDescriptors: roster:
    builtins.concatMap (descriptor: descriptor.leafStages roster) axisDescriptors;

  # Registered leaf stage (ordered before satisfiability and relations by
  # resolve.nix) that fails loud when a bare alias resolves to more than one
  # canonical member. Wording is distinct from the unknown-name/disjoint
  # diagnostic; every set axis exposes `ambiguous`, predicate axes contribute
  # none.
  aliasValidationCheck =
    registry: leaf:
    builtins.concatMap (
      name:
      map (alias: {
        kind = "ambiguous-alias";
        unit = leaf.value;
        label = leaf.label or null;
        source = leaf.source or null;
        axis = name;
        claims = leaf.claim;
        reason = "axis '${name}' claim uses bare alias '${alias}' that resolves to multiple canonical members -- qualify it as 'system/name' to disambiguate";
      }) (registry.${name}.ambiguous leaf.claim.${name})
    ) (builtins.attrNames registry);

  forbiddenKeysFor =
    axisDescriptors: scope:
    builtins.concatMap (
      descriptor:
      if builtins.elem scope descriptor.allowedScopes then
        [ ]
      else
        map (key: key // { inherit (descriptor) scopeError; }) descriptor.authorKeys
    ) axisDescriptors;

  # Project only entity keys named by the instantiated registry. A narrowed axis
  # whose raw entity is absent receives null; the engine's missing-context phase
  # rejects it before selection. Predicate axes contribute no key because their
  # ctxKey is null.
  contextFor =
    registry: rawCtx:
    lib.foldl' (
      ctx: axis:
      if axis.ctxKey == null then ctx else ctx // { ${axis.ctxKey} = rawCtx.${axis.ctxKey} or null; }
    ) { } (builtins.attrValues registry);

  ctxClaimFor =
    axisDescriptors: ctx:
    lib.foldl' (claim: descriptor: claim // descriptor.ctxClaim ctx) { } axisDescriptors;

  ctxLabelFor =
    axisDescriptors: ctx:
    let
      parts = builtins.filter (part: part != null) (
        map (descriptor: descriptor.ctxLabel ctx) axisDescriptors
      );
    in
    lib.concatStringsSep ", " parts;
in
{
  inherit
    include
    exclude
    global
    canonicalHostId
    mkSetAxis
    predicateAxis
    mkSetDescriptor
    mkPredicateDescriptor
    polarityFor
    descriptors
    hostUserRelation
    relations
    authorKeysFor
    claimKeysFor
    validateUnit
    claimOf
    registryFor
    relationsFor
    leafStagesFor
    aliasValidationCheck
    forbiddenKeysFor
    contextFor
    ctxClaimFor
    ctxLabelFor
    ;

  registry =
    {
      hosts ? [ ],
      users ? [ ],
    }:
    registryFor descriptors {
      inherit hosts users;
    };
}
