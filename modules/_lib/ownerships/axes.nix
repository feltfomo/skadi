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

  mkSetAxis =
    {
      key,
      members ? [ ],
    }:
    let
      observe =
        v:
        let
          materializedMembers = resolveMembers members v;
        in
        {
          inherit materializedMembers;
          satisfiable = materializedMembers != [ ];
          select =
            ctx:
            let
              selected = elem ctx.${key}.name materializedMembers;
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
        };
      ctxClaim =
        ctx:
        if ctx ? ${name} && ctx.${name} != null then { ${name} = include [ ctx.${name}.name ]; } else { };
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

  hostRoster = {
    membersField = "hosts";
    define = name: {
      kind = "host";
      inherit name;
    };
    project =
      { declarations, ... }:
      let
        hostDecls = builtins.filter (d: d.kind == "host") declarations;
        users = builtins.filter (d: d.kind == "user") declarations;
        named = builtins.concatMap (u: if u.hosts == null then [ ] else u.hosts) users;
      in
      {
        hosts = lib.unique (map (d: d.name) hostDecls ++ named);
      };
  };

  userRoster = {
    membersField = "users";
    define =
      name:
      {
        hosts ? null,
      }:
      {
        kind = "user";
        inherit name hosts;
      };
    project =
      { declarations, roster }:
      let
        users = builtins.filter (d: d.kind == "user") declarations;
        usersOn =
          h: map (u: u.name) (builtins.filter (u: u.hosts != null && builtins.elem h u.hosts) users);
      in
      {
        users = lib.unique (map (d: d.name) users);
        membership = lib.genAttrs roster.hosts usersOn;
        usersWithUnknownMembership = map (u: u.name) (builtins.filter (u: u.hosts == null) users);
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
