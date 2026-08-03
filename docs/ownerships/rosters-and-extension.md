# Rosters, descriptors, relations, and extension

The roster is the data boundary between ownership semantics and the fleet backend. Descriptors define how author syntax, context entities, registry axes, and roster projections connect.

## Default roster shape

```nix
{
  hosts = [ "x86_64-linux/khion" ];
  users = [ "feltfomo" ];

  membership = {
    "x86_64-linux/khion" = [ "feltfomo" ];
  };

  usersWithUnknownMembership = [ ];

  aliases = {
    host.khion = [ "x86_64-linux/khion" ];
    user.feltfomo = [ "feltfomo" ];
  };

  display = {
    host."x86_64-linux/khion" = "khion";
    user.feltfomo = "feltfomo";
  };

  dimensions = {
    gpu = {
      members = [ "nvidia" ];
      byHost."x86_64-linux/khion" = "nvidia";
    };
  };
}
```

Canonical IDs drive selection, membership, matrix keys, diffs, and diagnostics. `display` is presentation metadata.

## Standalone declarations

```nix
roster = ownerships.toRoster [
  (ownerships.define.host "khion" {
    system = "x86_64-linux";
    aliases = [ "khion" "desktop" ];
    dimensions.gpu = "nvidia";
  })

  (ownerships.define.user "feltfomo" {
    id = "feltfomo";
    hosts = [ "khion" ];
  })
];
```

`define.user` distinguishes:

- `hosts = null`, membership unknown;
- `hosts = [ ]`, known to live on no host;
- a non-empty list, known host membership.

Unknown membership can rescue a cross-axis relation because the roster cannot prove incompatibility. Known-empty membership does not.

User host references may use canonical IDs or unique aliases. Unknown and ambiguous aliases fail during roster construction.

## Descriptor contract

A set descriptor is created with `mkSetDescriptor`:

```nix
roleDescriptor = axes.mkSetDescriptor {
  name = "role";
  includeKey = "roles";
  excludeKey = "exceptRoles";
  includeOrder = 60;
  excludeOrder = 70;
  allowedScopes = [ "user" ];
  roster = {
    membersField = "roles";
    define = name: { kind = "role"; inherit name; };
    project = { declarations, ... }: {
      roles = ...;
    };
  };
};
```

A descriptor owns:

- unique axis name;
- unique ordered author keys;
- key shape validation and parsing;
- axis construction from a roster;
- allowed scopes and diagnostic wording;
- context claim and label projection;
- optional roster declaration and projection;
- optional leaf stages.

`mkPredicateDescriptor` creates a select-only predicate axis. It has no roster projector and no `ctxKey` entity.

Descriptor validation rejects malformed records, duplicate names, duplicate author keys, and duplicate key order.

## Axis contract

The engine sees only registered methods:

- `top`
- `narrow`
- `observe`
- `satisfiable`
- `select`
- `isTop`
- `ctxKey`
- `ambiguous`

It never branches on `host`, `user`, `when`, or a custom axis name.

For set axes, claims use include/exclude polarity. Narrowing is intersection for two includes, union for two excludes, and difference for mixed polarity.

## Relations

Relations register compatibility between two axes:

```nix
{
  name = "host-role-membership";
  leftAxis = "host";
  rightAxis = "role";
  unknownFor = roster: {
    left = [ ];
    right = [ ];
  };
  compatibleFor = roster: host: role:
    builtins.elem role (roster.roleMembership.${host} or [ ]);
  reason = hosts: roles:
    "no compatible host/role pair";
}
```

The generic relation checker applies these rules:

- a global side skips the relation;
- an empty side is left to same-axis satisfiability;
- any modeled unknown member rescues the relation;
- any compatible pair satisfies it;
- otherwise the leaf is impossible.

Relation validation rejects malformed records, duplicate names, and unknown axes.

## Adding an axis

1. Define one descriptor.
1. Add it to the descriptor list used by the desired surface.
1. Add standalone roster projection if the axis has finite members.
1. Add relation data separately when compatibility spans axes.
1. Prove author syntax, scope restrictions, context demand, selection, roster projection, and diagnostics.
1. Prove production defaults remain unchanged when the descriptor is test-only.

Do not edit `compose`, `pipeline`, selection, or matrix to add an axis.

## Adding a relation

Prove:

- known-compatible pair;
- known-incompatible pair;
- global left and right sides;
- empty sides;
- unknown-member rescue;
- diagnostic wording and order.

Keep compatibility in relation data and shared semantics in `engine.mkRelationCheck`.

## Den federation boundary

The whole-fleet adapter lives in `modules/_lib/den.nix`. It normalizes den hosts and users into the same declaration/projector path used standalone. Ownerships source files do not inspect den internals.

Host dimensions remain roster metadata unless a deliberate descriptor exposes them as author syntax. Adding dimensions must not silently expand the public claim-key set.
