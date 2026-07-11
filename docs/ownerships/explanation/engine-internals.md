# Engine internals

The surface is a thin translator. The actual work happens in a small, pure pipeline that never names `host` or `user` and never looks at a claim's value — it only calls an axis's methods and reads its declared `ctxKey`. That's the property that lets a new axis of any shape compose without touching the engine. This page is the model; the source (`engine.nix`, `axes.nix`, `merge.nix`) is small and worth reading alongside it.

## The pipeline

One entry point, a fixed sequence ([`engine.nix`](../../../modules/_lib/ownerships/engine.nix) `resolve`):

```
compose -> check -> assertCtx -> select -> strip -> merge
```

1. **compose** — walk the unit tree, emitting one leaf `{ claim; value; }` per config-bearing node. A child narrows its parent (`narrowClaim` runs each axis's `narrow`; a missing axis key defaults to that axis's `top`, so a claim can only ever narrow). A node with no value contributes only its claim to descendants.
2. **check** — run every check in the `checks` *list* over every leaf. Any diagnostic throws, all rendered together. Checks are a list so a new invariant is a new entry, never a branch inside the engine.
3. **assertCtx** — the build context must carry an entity only for an axis that both reads one (`ctxKey != null`) *and* is actually narrowed on by some leaf. It's derived per-resolve from the composed leaves, so a fully untagged spec resolves with no context at all.
4. **select** — keep a leaf only if, on every axis, its claim is global (`isTop`) *or* matches the context (`select`). Runs after check, so an impossible leaf errors for everyone while a leaf that just doesn't match this build falls away silently.
5. **strip + merge** — drop claims, fold the surviving values with the merge strategy.

The ordering is load-bearing. **check before select** is exactly what makes an *impossible* claim throw regardless of who's building, while an *inactive* one stays silent. Don't reorder it.

`isTop` short-circuits before both `select` and the context demand — so a global unit never reads context and never requires an entity. That's what keeps an untagged unit safe against a null or absent context.

## The axis model

Every axis implements `{ top; narrow; satisfiable; select; isTop; ctxKey }`. [`axes.nix`](../../../modules/_lib/ownerships/axes.nix) is the *one* file allowed to name `host` and `user`.

**Set axes** (`host`, `user`) carry a **polarity set**: `{ tag = "include" | "exclude"; set = [ name ]; }`.

- `include A` is exactly A. `exclude A` is everyone but A. `exclude []` is *global* — the two-sided identity, and therefore `top`.
- `narrow` is the polarity **meet**, deliberately roster-independent: `include ∩ include = include (intersection)`, `exclude ∩ exclude = exclude (union)`, mixed = `include (inc \ exc)`. "Globally owned" is expressible without ever materializing the fleet.
- `satisfiable` and `select` are the *only* roster-touching methods — they materialize the polarity set against the roster's members. An `include` of an unknown name collapses to `[]` (impossible); an `exclude` is the complement, so **a host added to the roster later is owned for free** by every `exclude`/global claim. That openness is the reason `narrow` stays roster-independent — don't materialize the fleet in `narrow` or you lose it.
- `ctxKey` is the context attr it reads (`ctx.host.name`, `ctx.user.name`).

**The predicate axis** (`when`) is select-only: `top` is const-true, `narrow` conjoins predicates, `satisfiable` is always true (no roster to contradict), `select` just runs the predicate, `isTop` is always false, and `ctxKey = null` (it needs no entity of its own; it runs against whatever context the binding scope assembles). A `when` that never matches is inactive, never independently impossible.

**The membership check** (`mkMembershipCheck`) is the one cross-axis check — it catches a user claimed under a host they don't live on. It lives in `axes.nix`, not the engine, because membership is a relation between exactly the host and user axes. It skips when either axis is global, when a single-axis miss already covers it, or when the user's host membership is unknown (see [roster and the den boundary](roster-and-den-boundary.md)).

## Merge, by shape

[`merge.nix`](../../../modules/_lib/ownerships/merge.nix) keys `mergeTwo` on value **shape**:

- **Attrsets** deep-recurse — structural union of keys, recursing into shared ones. Not policy, just structure.
- **Lists** go through a named strategy. Default is `ordered-concat` (`a ++ b`, preserving source order); `dedup-union` is available opt-in for set-like lists. Ordered-concat is the default on purpose — it matches NixOS list-merge convention and keeps migrated aspects byte-identical.
- **Scalars** hit the conflict policy. Default `strictScalar`: equal survives, differ throws. Only a genuine scalar clash between real co-owners is a [conflict](the-three-outcomes.md).

`mkMerge` takes the strategy table, the per-path strategy selector, and the conflict policy — pass different ones to change behavior without touching the recursion.

## Extend by data, not control flow

The design rule: **add a feature by handing the engine more data — never by editing the fold** (`compose` / `narrowClaim` / `resolve`). Because the engine only ever calls axis methods and reads `ctxKey`, there are exactly four seams:

- a **new axis** (a registration in the registry),
- a **new list merge strategy** (a table entry),
- a **new conflict policy** (a function passed to `mkMerge` — the deferred single-writer "lock" is exactly this),
- a **new check / stage** (an entry in the `checks` list — a coverage assertion like "exactly one bootloader" is this).

If a feature can't attach as one of those four, that's an engine design bug to fix, not a reason to special-case it inline. Walking one of these end-to-end is [add a new axis](../how-to/add-a-new-axis.md).

## See also

- [The three outcomes](the-three-outcomes.md) — what the pipeline produces, from an author's view.
- [Roster and the den boundary](roster-and-den-boundary.md) — the fleet data `satisfiable`/`select`/membership read.
- [Add a new axis](../how-to/add-a-new-axis.md) — the extensibility invariant, worked.
- [Error catalog](../reference/errors.md) — every throw the pipeline and surface can raise.
