# The authoring surface

An aspect writes config as a list of **units**. A unit is a plain attrset: whatever isn't a claim key is config, and the claim keys say who that config is for. This page is the mental model for the surface; for the exact key table see [claim keys](../reference/claim-keys.md).

## A unit tags itself

```nix
{
  hosts = [ "khion" "lumi" ];        # this unit is owned by two hosts
  environment.systemPackages = [ pkgs.pavucontrol ];
}
```

The `hosts` key is a claim. `environment.systemPackages` is config. There's no wrapper function pulling `host` out of context and no `for`/`let ... in` ceremony — the unit carries its own ownership, and the resolver reads the build context for you.

The claim keys:

- `hosts` / `exceptHosts` — own by this set of hosts, or by everyone *except* this set.
- `users` / `exceptUsers` — the same, on users.
- `when` — a predicate of the build context, for anything a name list can't express.

## Untagged means global — the default, not a special case

A unit with none of those keys is owned by everyone, everywhere. That's the baseline; a claim only ever *subtracts* from it. `kitty` is the whole point — it claims nothing, so it needs no wrapper and lands on every host and user:

```nix
den.aspects.kitty = program {
  pkg = pkgs: pkgs.kitty;
  files = [
    { dest = ".config/kitty/kitty.conf"; src = "${rootPath}/configs/kitty/kitty.conf"; }
  ];
};
```

There's no code path that treats "global" as an option value or a magic name — it falls out of the claim algebra, where the identity claim *is* global. See [engine internals](engine-internals.md) for why that matters (a host added to the fleet later is owned by every global unit for free).

## Narrow-only: a child can subset a parent, never widen it

Units nest with `children`. A child's effective claim is its parent's claim narrowed by its own — the intersection. So a child can carve a smaller set out of its parent, but it can never reach outside it:

```nix
{
  hosts = [ "khion" "lumi" ];
  children = [
    { hosts = [ "khion" ]; services.hypridle.enable = true; }  # khion only
  ];
}
```

A child that names something disjoint from its parent (e.g. `hosts = [ "lumi" ]` under a `khion`-only parent) narrows to the empty set. That's not a silent no-op — it's an [impossible error](the-three-outcomes.md). Widening is meaningless and unreachable by construction.

## The one collision to know about

Claim keys are read by name off the top of a unit. So a unit can't *also* carry a config value whose first path segment is a claim key. In practice that's only `users.*` — NixOS user management. Nothing on this surface owns `users.*` today, so there's no escape hatch for it yet; if you set `users` to a NixOS user attrset instead of a name list, you get a loud [author-time error](../reference/errors.md#author-time-surface), not a silently swallowed claim.

## See also

- [The two doors and `program`](doors-and-program.md) — how a unit list actually gets resolved.
- [The three outcomes](the-three-outcomes.md) — what happens to a unit that does, doesn't, or can't apply.
- [Claim keys](../reference/claim-keys.md) — the exact table and value shapes.
