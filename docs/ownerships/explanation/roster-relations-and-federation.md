# Roster, descriptors, and relations

The roster is the data boundary between ownership semantics and the fleet backend. The same descriptor projector builds standalone and den-backed rosters.

## Canonical identity

Host IDs are `"<system>/<name>"`, for example `x86_64-linux/khion`. Bare host names are aliases. A bare alias that maps to several canonical hosts fails loudly and must be qualified.

User IDs default to the user's name.

## Axis descriptors

A descriptor owns an axis end to end:

- registry name and axis constructor;
- author keys, order, validation, and parser;
- allowed scopes and scope-specific errors;
- context claim/label projection;
- optional standalone declaration and roster projection;
- optional leaf stages.

Production descriptors are host, user, and `when`. `mkSetDescriptor` and `mkPredicateDescriptor` are the extension factories.

The engine still sees only axis methods: `top`, `narrow`, `observe`, `satisfiable`, `select`, `isTop`, `ctxKey`, and `ambiguous`.

## Relations

Relations are a separate ordered registry. A relation names two axes, their unknown-member sets, a compatibility predicate, and diagnostic wording. The generic checker handles the shared rules:

- either global side skips the relation;
- an empty side is left to satisfiability;
- any modeled unknown member rescues the relation;
- any compatible pair satisfies it;
- otherwise the claim is impossible.

Host/user membership is the production relation. Tests register host/role to prove the checker isn't host/user-shaped.

## Whole-fleet den adapter

`modules/_lib/den.nix` enumerates every system in `den.hosts`, normalizes hosts and users into declarations, and calls the same roster projector used standalone. No other ownerships file reads den internals.

Host dimensions are preserved as roster data:

```nix
roster.dimensions.<dimension> = {
  members = [ ... ];
  byHost."<canonical-host-id>" = <value>;
};
```

They are federation metadata and a foundation for future projected axes. The production descriptor list does not automatically turn dimensions into author keys.

## Unknown membership

Standalone `define.user` distinguishes:

- `hosts = null`: membership unknown, relation checks rescue the user;
- `hosts = []`: known to live nowhere;
- a non-empty list: known membership.

The den adapter always knows which host emitted a user, so it produces no unknown-membership users.
