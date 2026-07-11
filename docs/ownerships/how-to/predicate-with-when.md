# Gate on a predicate with `when`

**Goal:** own a unit by some property of the build target that a host/user name list can't express — a GPU vendor, a form factor, a role flag.

Use the `when` claim: a predicate function of the build context. It's the escape hatch for "select by attribute, not by name."

## Recipe

```nix
{
  when = { host, ... }: host.gpu == "nvidia";
  environment.systemPackages = [ pkgs.nvtopPackages.nvidia ];
}
```

`when` receives the same context the resolve was handed — `{ host, user }` at user scope, `{ host }` host-only — and the unit applies only where it returns `true`. Here it lands on hosts whose entity reports an nvidia GPU and is [inactive](../explanation/the-three-outcomes.md#1-inactive--silent) everywhere else.

> This is an illustrative shape — no shipped skadi aspect uses `when` yet. Reach for it only when a name list genuinely can't say what you mean; prefer `hosts`/`users` when it can, because names are checkable against the roster and predicates aren't.

## How it behaves differently from a name claim

- **It's select-only.** `when` has no roster to contradict, so it's never independently [impossible](../explanation/the-three-outcomes.md#2-impossible--loud-error) — a predicate that never matches is just inactive. A typo'd *host name*, by contrast, is impossible and loud. You lose that safety net with `when`; that's the tradeoff.
- **It reads whatever the context carries.** `when` declares no entity of its own (its axis `ctxKey` is `null`), so it runs against the context the binding scope assembled. Make sure the attribute you read (`host.gpu` here) actually exists on the entity, or the predicate throws when it evaluates.
- **It narrows like everything else.** Nested `when`s conjoin (both must hold), and `when` combines with `hosts`/`users` on the same unit by AND across axes.

## See also

- [The authoring surface](../explanation/authoring-surface.md) — `when` among the claim keys.
- [Engine internals](../explanation/engine-internals.md) — the predicate axis (select-only, `ctxKey = null`).
- [Claim keys](../reference/claim-keys.md) — `when`'s signature per scope.
