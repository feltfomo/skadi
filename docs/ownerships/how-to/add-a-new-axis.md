# Add a new axis *(advanced)*

> **Advanced / rarely needed.** Most work is authoring claims, not extending the engine. Reach here only when you genuinely need to own config along a *new dimension* — not a host, not a user — and `when` isn't enough because you want roster-checked names rather than an opaque predicate. This is the concrete payoff of the extensibility invariant from [engine internals](../explanation/engine-internals.md#extend-by-data-not-control-flow): a new axis is *added data*, never an edit to the fold.

## What an axis has to provide

Every axis implements the same interface the engine calls blindly ([`axes.nix`](../../../modules/_lib/ownerships/axes.nix)):

```nix
{ top; narrow; satisfiable; select; isTop; ctxKey }
```

- `top` — the identity claim ("globally owned on this axis").
- `narrow` — meet two claims; must be associative and must only ever shrink. A missing key on a unit defaults to `top`, so this is what makes claims narrow-only.
- `satisfiable` — does the claim match *any* roster member? (`false` → [impossible](../explanation/the-three-outcomes.md#2-impossible--loud-error)).
- `select` — does the claim match *this* build's context entity?
- `isTop` — is this claim global? (short-circuits select and the context demand).
- `ctxKey` — the context attr this axis reads, or `null` if it needs none (like `when`).

If your dimension is a set of names, reuse the polarity-set machinery `host`/`user` are built on rather than writing meet logic from scratch — you get `include`/`exclude`, roster-independent `narrow`, and free open-world `exclude` semantics.

## The four steps

1. **Register the axis** in the registry (`engineArgsFor`, [`resolve.nix`](../../../modules/_lib/ownerships/resolve.nix)) with a claim key and its `ctxKey`. That's the whole engine change — there isn't one; you're adding a registration.
2. **Surface the claim key** so the translator lifts it off a unit like the others, and add it to the reserved-key set so it can't be mistaken for a config path ([`surface.nix`](../../../modules/_lib/ownerships/surface.nix)).
3. **Feed the roster** whatever `satisfiable`/`select` need for the new dimension, in both backends (the [den adapter](../explanation/roster-and-den-boundary.md) and `define.*`/`toRoster`), so it's populated whether or not den is present.
4. **Add a cross-axis check only if the dimension relates to another** — the way membership relates host and user. Register it in the `checks` list; don't inline it in the engine.

## What you must not do

Don't edit `compose`, `narrowClaim`, or `resolve` in [`engine.nix`](../../../modules/_lib/ownerships/engine.nix). If a new axis seems to require touching the fold, the axis interface is missing something — fix the interface, not the engine. The engine staying axis-agnostic is the invariant that keeps every existing axis composing with your new one for free.

## See also

- [Engine internals](../explanation/engine-internals.md) — the axis model and the four seams in full.
- [Roster shape](../reference/roster-shape.md) — what a new dimension has to add to the roster.
- [Error catalog](../reference/errors.md) — the diagnostics a check can raise.
