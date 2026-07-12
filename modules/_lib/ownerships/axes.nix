# _lib/ownerships/axes.nix
#
# The set-axis value type (a polarity set) plus host + user registered on the
# engine, and the select-only predicate axis the `when` claim runs
# on. This is the one file allowed to name host/user; the engine below never
# does. A set axis carries a polarity set and reads an entity's identity
# (ctx.<axis>.name); a predicate axis reads no entity of its own (ctxKey =
# null) and just runs its function against whatever ctx the caller assembles.
_:
let
  inherit (builtins) elem filter;

  # a polarity set: { tag = "include" | "exclude"; set = [name]; }. include A is
  # exactly A; exclude A is everyone but A; exclude [] is global -- the identity.
  mk = tag: set: { inherit tag set; };
  include = mk "include";
  exclude = mk "exclude";
  global = exclude [ ];
  isGlobal = v: v.tag == "exclude" && v.set == [ ];

  # plain set ops on name lists, order-preserving so merges stay deterministic.
  inter = a: b: filter (x: elem x b) a;
  diff = a: b: filter (x: !(elem x b)) a;
  union = a: b: a ++ filter (x: !(elem x a)) b;

  # meet of two polarity sets -- deliberately roster-INDEPENDENT, so "globally
  # owned" is expressible without materializing the fleet:
  #   include A ,, include B = include (A n B)
  #   exclude A ,, exclude B = exclude (A u B)
  #   include A ,, exclude B = include (A \ B)
  # exclude [] is the two-sided identity, which is why it is top.
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

  # materialize a polarity set against the roster's members for this axis.
  # include keeps the members it names (a typo collapses to [] -> impossible);
  # exclude is the complement, so a host added to the roster later is owned for
  # free -- the openness win over a frozen enumeration.
  resolveMembers = members: v: if v.tag == "include" then inter v.set members else diff members v.set;

  # A set axis materializes a claim once, then all roster-dependent answers
  # read that observation. Keeping selection and satisfiability on the same
  # names prevents explanations from drifting from the decision they describe.
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
      # is this claim the global (exclude []) identity? the engine asks isTop
      # before select, so a globally-owned axis never reads ctx, and before
      # demanding a ctx entity, so an untagged axis demands none. exclude
      # ["lumi"] and include [...] are NOT global -- they narrow, so they still
      # read ctx and still demand an entity.
      isTop = isGlobal;
      # the ctx attribute this axis reads its entity from -- assertCtx requires a
      # ctx entry here only when a claim actually narrows on this axis.
      ctxKey = key;
    };

  # A predicate has no member set to invent. Its observation carries only the
  # real predicate decision, while satisfiability stays constant because no
  # roster can contradict it.
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
      # a predicate reads ctx freeform, so which entities it touches can't be
      # derived from the claim -- it just runs against whatever ctx the scope that
      # binds it assembles. a scope that owns no host won't populate ctx.host, so a
      # predicate reading it there fails inside the predicate itself; honoring the
      # ctx its scope provides is the predicate's own contract, not something the
      # engine guards -- catching it would swallow genuine predicate bugs too.
      select = pred: ctx: ((observe pred).select ctx).selected;
      # functions can't be compared in nix, so a predicate can't test itself
      # against the top predicate -- and it needs no ctx entity anyway (ctxKey =
      # null keeps it out of assertCtx), so it never reports itself top. the
      # identity predicate _: true ignores ctx, so running it is safe even under a
      # null build context.
      isTop = _: false;
      ctxKey = null;
    };

  # host<->user membership as a cross-axis check. the set axes already guarantee
  # each axis resolves to at least one entity; this catches the pair that cannot
  # co-exist -- a user claimed under a host it does not live on. it names host
  # and user because membership is a relation between exactly those two axes, so
  # it belongs here rather than in the axis-agnostic engine. the returned
  # function matches the engine's check shape: registry -> leaf -> [ diagnostic ].
  mkMembershipCheck =
    {
      hosts ? [ ],
      users ? [ ],
      membership ? { },
      usersWithUnknownMembership ? [ ],
    }:
    _registry: leaf:
    let
      hostClaim = leaf.claim.host;
      userClaim = leaf.claim.user;
      hs = resolveMembers hosts hostClaim;
      us = resolveMembers users userClaim;
      # a user whose host membership is unknown (a define.* user that named no
      # hosts) could live anywhere, so it always admits a pairing -- this is the
      # degrade-to-same-axis-only path.
      rescued = builtins.any (u: elem u usersWithUnknownMembership) us;
      pairs = builtins.any (h: builtins.any (u: elem u (membership.${h} or [ ])) us) hs;
    in
    # a global claim on either axis means the unit is not asserting host x user
    # co-ownership there, so membership cannot contradict it; and an empty hs/us
    # is a single-axis miss that satisfiableCheck already reports, so skip both
    # to keep one root cause to one diagnostic.
    if isGlobal hostClaim || isGlobal userClaim || hs == [ ] || us == [ ] || rescued || pairs then
      [ ]
    else
      [
        {
          kind = "impossible";
          unit = leaf.value;
          # carry the same optional identity fields satisfiableCheck's
          # diagnostic does, so a labeled synthetic leaf renders through
          # identifyUnit here exactly as it does on the single-axis path.
          label = leaf.label or null;
          source = leaf.source or null;
          axes = [
            "host"
            "user"
          ];
          claims = leaf.claim;
          reason = "no user in { ${builtins.concatStringsSep ", " us} } lives on any host in { ${builtins.concatStringsSep ", " hs} } -- this host/user co-ownership can never apply";
        }
      ];
in
{
  inherit
    include
    exclude
    global
    mkSetAxis
    predicateAxis
    mkMembershipCheck
    ;

  # host + user. members come from the roster, stubbed here for now; the real
  # den-backed roster wires through _lib/den.nix later in the same shape.
  registry =
    {
      hosts ? [ ],
      users ? [ ],
    }:
    {
      host = mkSetAxis {
        key = "host";
        members = hosts;
      };
      user = mkSetAxis {
        key = "user";
        members = users;
      };
    };
}
