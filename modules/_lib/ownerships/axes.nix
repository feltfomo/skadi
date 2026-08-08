# _lib/ownerships/axes.nix
#
# axis implementations, authoring descriptors, and cross-axis relation data.
# the engine consumes registries built from these records; it never learns axis
# names, author keys, roster fields, or which scopes may use them. new axes and
# relations extend data here instead of branching the translator or resolver.
{ lib }:
let
  krisis = import ../krisis { inherit lib; };
  axiom = import ../axiom { inherit lib; };
  inherit (axiom)
    canonical
    registry
    schema
    validation
    ;

  axisProblem = krisis.mkDiagnosticFactory {
    severity = "error";
    codePrefix = "ownerships";
  };

  reporter = krisis.mkReporter { formatDiagnostic = krisis.renderPlain; };

  finish = validation.finish reporter.fail;

  failAxis = reporter.failOne;

  # author-key shape errors are the plain strings the descriptor author wrote,
  # not krisis records, so they join on their own rather than going through the
  # diagnostic renderer
  finishShape = validation.finish (diagnostics: throw (lib.concatStringsSep "\n" diagnostics));

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

  # shared alias/canonical resolution, used by every set axis and by the
  # registered alias-validation stage. a claim name that is already a canonical
  # member is kept as-is; otherwise it expands through the roster-provided alias
  # map (default {} = identity). an unknown name stays itself and falls through
  # to the existing unknown-name/disjoint diagnostic.
  canonicalizeName =
    aliasMap: members: name:
    if elem name members then [ name ] else aliasMap.${name} or [ name ];

  canonicalizeSet =
    aliasMap: members: set:
    lib.unique (builtins.concatMap (canonicalizeName aliasMap members) set);

  # bare aliases that resolve to more than one canonical member. a bare claim
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
      failAxis (axisProblem {
        code = "claim-polarity";
        message = "a unit cannot set both '${positive}' and '${negative}' -- pick the set or its complement";
      })
    else if unit ? ${positive} then
      include unit.${positive}
    else if unit ? ${negative} then
      exclude unit.${negative}
    else
      null;

  defaultScopeError =
    scope: key: value:
    "ownerships: a ${scope}-scope unit sets '${key}' = ${krisis.safeRender value} -- this ownership axis is unavailable in ${scope} scope";

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

  # canonical host identity is "<system>/<name>"; a bare name is an alias. a
  # one-arg `define.host "khion"` stays a standalone declaration (system
  # "standalone", bare-name alias) so existing callers keep byte-identical
  # resolve/config output; the optional attrs form federates a host onto a real
  # system and can carry extra aliases and dimension data.
  canonicalHostId =
    system: name:
    canonical.qualified {
      namespace = system;
      inherit name;
    };

  aliasesFor =
    entries:
    let
      registrations = builtins.concatMap (
        entry:
        map (alias: {
          name = alias;
          value = entry.id;
        }) entry.aliases
      ) entries;
      grouped = builtins.groupBy (registration: registration.name) registrations;
    in
    lib.mapAttrs (_: group: lib.unique (map (registration: registration.value) group)) grouped;

  hostRoster = {
    membersField = "hosts";
    # a host ctx entity resolves to its canonical id, an explicit id wins,
    # otherwise it is derived from the entity's own system/name. a caller adds
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
              failAxis (axisProblem {
                code = "roster-unknown-host";
                message = "user roster references unknown host '${name}'";
              })
            else if builtins.length matches > 1 then
              failAxis (axisProblem {
                code = "roster-ambiguous-host";
                message = "user roster host alias '${name}' is ambiguous; use a canonical system/name";
              })
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
      "ownerships: a system-scope (host-only) unit sets '${key}' = ${krisis.safeRender value} -- a host-only slice binds no user, so it cannot narrow on users. drop the user claim or resolve this unit at user scope."
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

  requiredField = code: subject: field: expected: predicate: {
    required = true;
    validate = predicate;
    onMissing =
      _record:
      axisProblem {
        inherit code;
        message = "${subject} is missing required field '${field}'";
      };
    onInvalid =
      _record: value:
      axisProblem {
        inherit code;
        message = "${subject} field '${field}' must be ${expected}; got ${builtins.typeOf value}";
      };
  };

  stringField =
    code: subject: field:
    requiredField code subject field "a string" builtins.isString;

  functionField =
    code: subject: field:
    requiredField code subject field "a function" builtins.isFunction;

  # a registration that got its own name wrong can't be named in its own
  # diagnostic, so it falls back to where it sits in the list
  subjectFor =
    noun: index: registration:
    if builtins.isAttrs registration && registration ? name && builtins.isString registration.name then
      "${noun} '${registration.name}'"
    else
      "${noun} at index ${toString index}";

  descriptorCode = "descriptor-malformed";

  # open, because a descriptor is free to carry data these axes don't read
  authorKeySchema =
    subject: index:
    let
      keySubject = "${subject} author key ${toString index}";
    in
    schema.compile {
      allowUnknown = true;
      onRecord =
        value:
        axisProblem {
          code = descriptorCode;
          message = "${keySubject} must be an attribute set; got ${builtins.typeOf value}";
        };
      order = [
        "name"
        "order"
        "valid"
        "shapeError"
      ];
      fields = {
        name = stringField descriptorCode keySubject "name";
        order = requiredField descriptorCode keySubject "order" "an integer" builtins.isInt;
        valid = functionField descriptorCode keySubject "valid";
        shapeError = functionField descriptorCode keySubject "shapeError";
      };
    };

  descriptorSchema =
    subject:
    schema.compile {
      allowUnknown = true;
      onRecord =
        value:
        axisProblem {
          code = descriptorCode;
          message = "${subject} must be an attribute set; got ${builtins.typeOf value}";
        };
      order = [
        "name"
        "authorKeys"
        "roster"
        "allowedScopes"
        "parse"
        "axisFor"
        "ctxClaim"
        "ctxLabel"
        "leafStages"
        "scopeError"
      ];
      fields = {
        name = stringField descriptorCode subject "name";
        authorKeys = requiredField descriptorCode subject "authorKeys" "a list" builtins.isList;
        roster = requiredField descriptorCode subject "roster" "an attribute set or null" (
          value: value == null || builtins.isAttrs value
        );
        allowedScopes = requiredField descriptorCode subject "allowedScopes" "a list of strings" (
          value: builtins.isList value && lib.all builtins.isString value
        );
        parse = functionField descriptorCode subject "parse";
        axisFor = functionField descriptorCode subject "axisFor";
        ctxClaim = functionField descriptorCode subject "ctxClaim";
        ctxLabel = functionField descriptorCode subject "ctxLabel";
        leafStages = functionField descriptorCode subject "leafStages";
        scopeError = functionField descriptorCode subject "scopeError";
      };
    };

  descriptorResult =
    index: descriptor:
    let
      subject = subjectFor "axis descriptor" index descriptor;
      shape = descriptorSchema subject descriptor;
      keyResults = lib.optionals (
        builtins.isAttrs descriptor && descriptor ? authorKeys && builtins.isList descriptor.authorKeys
      ) (lib.imap0 (keyIndex: key: authorKeySchema subject keyIndex key) descriptor.authorKeys);
    in
    validation.fromDiagnostics (validation.collect (
      [ shape.diagnostics ] ++ map (result: result.diagnostics) keyResults
    )) descriptor;

  duplicateDescriptorDiagnostics =
    axisDescriptors:
    (registry.compile {
      registrations = axisDescriptors;
      keyOf = descriptor: descriptor.name;
      onDuplicate =
        key: _registrations:
        axisProblem {
          code = "descriptor-duplicate-name";
          message = "duplicate axis descriptor name '${key}'";
        };
    }).diagnostics;

  duplicateAuthorKeyDiagnostics =
    authorKeys:
    validation.collect [
      (registry.compile {
        registrations = authorKeys;
        keyOf = key: key.name;
        onDuplicate =
          key: _registrations:
          axisProblem {
            code = "descriptor-duplicate-key";
            message = "duplicate ownership author key '${key}'";
          };
      }).diagnostics
      (registry.compile {
        registrations = authorKeys;
        keyOf = key: toString key.order;
        onDuplicate =
          key: _registrations:
          axisProblem {
            code = "descriptor-duplicate-order";
            message = "duplicate ownership author-key order ${key}";
          };
      }).diagnostics
    ];

  # shape runs to completion before the duplicate registries, which read the
  # very fields the shape stage is still deciding are there
  validateDescriptors =
    axisDescriptors:
    let
      shaped = validation.sequence (lib.imap0 descriptorResult axisDescriptors);
    in
    finish (
      if shaped.diagnostics != [ ] then
        shaped
      else
        validation.fromDiagnostics (validation.collect [
          (duplicateDescriptorDiagnostics axisDescriptors)
          (duplicateAuthorKeyDiagnostics (
            builtins.concatMap (descriptor: descriptor.authorKeys) axisDescriptors
          ))
        ]) axisDescriptors
    );

  validateRelations =
    axisDescriptors: relationRegistrations:
    let
      relationCode = "relation-malformed";
      relationSchema =
        subject:
        schema.compile {
          allowUnknown = true;
          onRecord =
            value:
            axisProblem {
              code = relationCode;
              message = "${subject} must be an attribute set; got ${builtins.typeOf value}";
            };
          order = [
            "name"
            "leftAxis"
            "rightAxis"
            "unknownFor"
            "compatibleFor"
            "reason"
          ];
          fields = {
            name = stringField relationCode subject "name";
            leftAxis = stringField relationCode subject "leftAxis";
            rightAxis = stringField relationCode subject "rightAxis";
            unknownFor = functionField relationCode subject "unknownFor";
            compatibleFor = functionField relationCode subject "compatibleFor";
            reason = functionField relationCode subject "reason";
          };
        };

      checkedDescriptors = validateDescriptors axisDescriptors;
      axisNames = map (descriptor: descriptor.name) checkedDescriptors;

      subjectAt = index: relation: subjectFor "relation" index relation;

      shaped = validation.sequence (
        lib.imap0 (
          index: relation:
          validation.fromDiagnostics (relationSchema (subjectAt index relation) relation).diagnostics relation
        ) relationRegistrations
      );

      unknownAxisDiagnostics =
        index: relation:
        builtins.concatMap
          (
            side:
            validation.optional (!(builtins.elem relation.${side} axisNames)) (axisProblem {
              code = "relation-unknown-axis";
              message = "${subjectAt index relation} references unknown axis '${relation.${side}}' as ${side}";
            })
          )
          [
            "leftAxis"
            "rightAxis"
          ];
    in
    finish (
      if shaped.diagnostics != [ ] then
        shaped
      else
        validation.fromDiagnostics (validation.collect (
          [
            (registry.compile {
              registrations = relationRegistrations;
              keyOf = relation: relation.name;
              onDuplicate =
                key: _registrations:
                axisProblem {
                  code = "relation-duplicate-name";
                  message = "duplicate relation name '${key}'";
                };
            }).diagnostics
          ]
          ++ lib.imap0 unknownAxisDiagnostics relationRegistrations
        )) relationRegistrations
    );

  compileDescriptors =
    axisDescriptors:
    let
      descriptors = validateDescriptors axisDescriptors;
      authorKeys = builtins.sort (a: b: a.order < b.order) (
        builtins.concatMap (descriptor: descriptor.authorKeys) descriptors
      );
    in
    {
      inherit descriptors authorKeys;
      claimKeys = map (key: key.name) authorKeys;
      rosterDescriptors = builtins.filter (descriptor: descriptor.roster != null) descriptors;
    };

  authorKeysFor = axisDescriptors: (compileDescriptors axisDescriptors).authorKeys;

  claimKeysFor = axisDescriptors: (compileDescriptors axisDescriptors).claimKeys;

  # every misplaced claim key on the unit, not just the first -- a nixos `users`
  # attrset landing on the ownership key used to hide a second bad key behind it
  validateUnitWith =
    authorKeys: unit:
    finishShape (
      validation.fromDiagnostics (builtins.concatMap (
        key:
        validation.optional (unit ? ${key.name} && !key.valid unit.${key.name}) (
          key.shapeError unit.${key.name}
        )
      ) authorKeys) unit
    );

  validateUnit = axisDescriptors: validateUnitWith (compileDescriptors axisDescriptors).authorKeys;

  claimOf =
    axisDescriptors: unit:
    lib.foldl' (claim: descriptor: claim // descriptor.parse unit) { } axisDescriptors;

  registryFrom =
    axisDescriptors: roster:
    builtins.listToAttrs (
      map (descriptor: {
        inherit (descriptor) name;
        value = descriptor.axisFor roster;
      }) axisDescriptors
    );

  registryFor = axisDescriptors: registryFrom (validateDescriptors axisDescriptors);

  registryForCompiled = descriptorSet: registryFrom descriptorSet.descriptors;

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

  # registered leaf stage (ordered before satisfiability and relations by
  # resolve.nix) that fails loud when a bare alias resolves to more than one
  # canonical member. wording is distinct from the unknown-name/disjoint
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

  # project only entity keys named by the instantiated registry. a narrowed axis
  # whose raw entity is absent receives null; the engine's missing-context phase
  # rejects it before selection. predicate axes contribute no key because their
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
    validateDescriptors
    validateRelations
    compileDescriptors
    authorKeysFor
    claimKeysFor
    validateUnitWith
    validateUnit
    claimOf
    registryFor
    registryForCompiled
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
