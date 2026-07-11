# Glossary

Short definitions for the terms used across these docs. Where a term has its own page, follow the link.

- **Aspect** — a skadi feature module (`kitty`, `audio`, `hyprland`, `notion-sync`). Authors ownership through [`program`](doors-and-program-args.md#program-spec).
- **Unit** — a plain attrset carrying config plus optional claim keys. The atom of ownership. See [the authoring surface](../explanation/authoring-surface.md).
- **Claim / claim key** — a key that says who a unit is for: `hosts`, `users`, `exceptHosts`, `exceptUsers`, `when`. See [claim keys](claim-keys.md).
- **Global / untagged** — a unit (or an axis of one) with no claim: owned by everyone. The identity claim, not a special case.
- **Axis** — a dimension ownership can narrow along: `host`, `user`, and the `when` predicate. Implements `{ top; narrow; satisfiable; select; isTop; ctxKey }`. See [engine internals](../explanation/engine-internals.md#the-axis-model).
- **Polarity set** — the value a set axis carries: `{ tag = "include" | "exclude"; set = [ name ]; }`. `include A` is A; `exclude A` is everyone but A; `exclude []` is global.
- **Narrow (meet)** — combining two claims on an axis into their intersection. Narrow-only: a claim can shrink a parent, never widen it.
- **`top` / `isTop`** — the global claim on an axis, and the test for it. `isTop` short-circuits selection and the context demand.
- **`ctxKey`** — the context attribute an axis reads (`host.name`, `user.name`), or `null` for an axis that reads none (`when`).
- **Leaf** — a `{ claim; value; }` produced by `compose` for one config-bearing node.
- **Scope** — what the build context carries: **user scope** (`host` + `user`) or **host-only** (`host`, no user). See [the two doors](../explanation/doors-and-program.md).
- **Door** — a resolve entry bound to a roster: `mkResolve` (user scope) or `mkResolveSystem` (host-only). See [doors and `program` args](doors-and-program-args.md).
- **`program`** — the front door aspects actually use: a spec DSL (`pkg`/`files`/`templates`/`nixos`/…) that forwards claims into the doors. See [the two doors and `program`](../explanation/doors-and-program.md).
- **Roster** — the fleet data: `{ hosts; users; membership; usersWithUnknownMembership }`. See [roster shape](roster-shape.md).
- **Membership** — which users live on which host; the one cross-axis relation, checked by `mkMembershipCheck`.
- **The den boundary** — `modules/_lib/den.nix`, the sole file allowed to read den internals (to build the roster). See [roster and the den boundary](../explanation/roster-and-den-boundary.md).
- **The three outcomes** — inactive (silent), impossible (loud), conflict (loud). The complete set of resolve results. See [the three outcomes](../explanation/the-three-outcomes.md).
- **Merge strategy / conflict policy** — how surviving values combine: attrsets recurse, lists use a named strategy (`ordered-concat` default), scalars use a conflict policy (`strictScalar` default). See [engine internals](../explanation/engine-internals.md#merge-by-shape).

## See also

- [Ownerships index](../README.md) — the one-screen model and the source map.
