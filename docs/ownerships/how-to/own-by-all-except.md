# Own by everyone except some hosts/users

**Goal:** own a unit globally *minus* a few hosts or users — "everyone but lumi," "all users except the shared account."

Use the negative claim keys, `exceptHosts` / `exceptUsers`. They express the complement directly, so you don't have to enumerate every host you *do* want (and you don't have to remember to edit the list when a host joins the fleet).

## Recipe

```nix
{
  exceptHosts = [ "lumi" ];
  programs.git.enable = true;   # every host except lumi
}
```

`exceptHosts = [ "lumi" ]` is the polarity set `exclude ["lumi"]` — the complement of lumi. A host added later is owned by this unit automatically, because `exclude` is defined against the roster's members at selection time, not frozen at authoring. That's the payoff over listing hosts positively.

`exceptUsers` works identically on the user axis (user scope only).

## Don't set both polarities on one axis

A single unit can't set both `hosts` and `exceptHosts` (or both `users` and `exceptUsers`) — pick the set or its complement. Setting both throws at author time; see [`polarityFor`](../reference/errors.md#author-time-surface).

## "A except B" when the base isn't global: nest to narrow

If the base is already a positive set and you want to subtract from it, don't try to cram both onto one unit — nest. The child narrows the parent:

```nix
{
  hosts = [ "khion" "lumi" ];
  children = [
    { exceptHosts = [ "lumi" ]; programs.foo.enable = true; }  # khion only
  ];
}
```

The child's `exclude ["lumi"]` meets the parent's `include ["khion" "lumi"]` to `include ["khion"]`. Note that narrowing a positive set until it's empty is [impossible](../explanation/the-three-outcomes.md#2-impossible--loud-error), not silent — e.g. `exceptHosts = [ "khion" "lumi" ]` under that parent would throw.

## See also

- [The authoring surface](../explanation/authoring-surface.md) — narrow-only nesting.
- [The three outcomes](../explanation/the-three-outcomes.md) — what an over-narrowed set does.
- [Claim keys](../reference/claim-keys.md) — the positive/negative pairs and their value shapes.
