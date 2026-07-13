# Add a new axis *(advanced)*

> **Advanced / rarely needed.** Most work is authoring claims, not extending the engine. Add an axis only for a real ownership dimension with roster-checked names. If a predicate is enough, use `when`.

An axis is one descriptor in [`axes.nix`](../../../modules/_lib/ownerships/axes.nix). The descriptor owns the entire path from author syntax to resolution:

- its registry name and axis implementation;
- author keys and parsing;
- reserved-key validation;
- scopes where authors may use it;
- optional standalone roster declaration and projection;
- optional leaf checks.

The engine still consumes only `{ top; narrow; observe; satisfiable; select; isTop; ctxKey; }`. Don't edit `compose`, `narrowClaim`, `pipeline`, or `resolve` to add an axis.

## A set-backed axis

Use `mkSetDescriptor` for a named dimension with include/exclude syntax. This example is deliberately local; production defaults stay host, user, and `when` until a real role requirement exists.

```nix
let
  axes = import ./modules/_lib/ownerships/axes.nix { inherit lib; };

  role = axes.mkSetDescriptor {
    name = "role";
    includeKey = "roles";
    excludeKey = "exceptRoles";
    includeOrder = 60;
    excludeOrder = 70;
    allowedScopes = [ "user" ];

    roster = {
      membersField = "roles";
      define = name: {
        kind = "role";
        inherit name;
      };
      project =
        { declarations, ... }:
        {
          roles = lib.unique (
            map (declaration: declaration.name) (
              builtins.filter
                (declaration: declaration.kind == "role")
                declarations
            )
          );
        };
    };
  };

  descriptors = axes.descriptors ++ [ role ];
  ownerships = import ./modules/_lib/ownerships/surface.nix {
    inherit lib descriptors;
  };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion")
    (ownerships.define.user "feltfomo" { hosts = [ "khion" ]; })
    (ownerships.define.role "desktop")
    (ownerships.define.role "laptop")
  ];
in
ownerships.mkResolve roster [
  {
    roles = [ "desktop" ];
    programs.example.enable = true;
  }
]
```

That one descriptor supplies both `roles = [...]` and `exceptRoles = [...]`, reserves those words on authored units, registers a `role` axis backed by `roster.roles`, adds `define.role`, and teaches `toRoster` how to project role declarations.

`allowedScopes = [ "user" ]` also makes a role claim illegal through `mkResolveSystem`. The surface's generic recursive scope guard catches the claim at author time, including when it sits under `children`.

## Predicate axes

A select-only dimension can use `mkPredicateDescriptor`. It has the same outer descriptor contract but no roster projection:

```nix
axes.mkPredicateDescriptor {
  name = "when";
  authorKey = "when";
  order = 50;
  allowedScopes = [ "user" "system" ];
}
```

Descriptors with `roster = null` are skipped by the roster factory. They don't create empty roster fields.

## Checks belong to the descriptor only when the axis needs one

A descriptor may contribute `leafStages = roster: [...]`. `engineArgsFor` appends those stages after the shared satisfiability check.

Don't turn that into a generic relation system while adding an ordinary axis. The existing host/user membership rule remains a host/user-specific leaf check. A general cross-axis relation registry needs its own requirement and design.

## What adding a descriptor must prove

A new set-backed descriptor needs tests for:

- include and exclude author syntax;
- standalone roster projection and declaration;
- selection with its context entity;
- a narrowed claim with the entity missing from context, which must throw through the structured diagnostic path;
- every scope restriction, including a nested claim under `children`;
- unchanged production defaults when the descriptor is test-only.

Keep the descriptor test-only until the ownership dimension has a real production requirement. A speculative axis still expands the authoring language and roster contract even if nobody uses it.

## See also

- [Engine internals](../explanation/engine-internals.md) — the fixed axis-agnostic pipeline.
- [Roster shape](../reference/roster-shape.md) — the default host/user projection.
- [Error catalog](../reference/errors.md) — author-time and structured resolution failures.
