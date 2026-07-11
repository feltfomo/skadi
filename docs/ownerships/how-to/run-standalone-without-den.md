# Run standalone without den

**Goal:** resolve ownership units with no den present — in a test, a scratch eval, or another project that just wants the engine. Ownerships is den-independent; den is only ever behind the `den.nix` adapter.

You need two things: a **roster** (what the fleet contains) and a **resolve** bound to it. Build the roster with `define.*` + `toRoster`, then use the same claim vocabulary you'd use inside skadi.

## Recipe

```nix
let
  ownerships = import ./modules/_lib/ownerships/surface.nix { inherit lib; };

  roster = ownerships.toRoster [
    (ownerships.define.host "khion")
    (ownerships.define.host "lumi")
    (ownerships.define.user "feltfomo" { hosts = [ "khion" ]; })
  ];

  resolve = ownerships.mkResolve roster;   # user-scope door, bound to the roster
in
(resolve [
  { hosts = [ "khion" ]; programs.foo.enable = true; }
  { environment.etc."x".text = "global"; }
]) { host = { name = "khion"; }; user = { name = "feltfomo"; }; }
```

The claim keys are identical to the den-bound path — that's the point. Only roster *construction* differs; nothing about how a unit labels itself changes. For host-only slices use `ownerships.mkResolveSystem roster` and hand it a `{ host = { name = ...; }; }` context with no user.

## The `hosts = null` vs `hosts = []` distinction

In `define.user`, the `hosts` argument controls the membership check:

- **omit it / `hosts = null`** — membership *unknown*; the user is let through under any host. Use this when you don't want membership enforced.
- **`hosts = [ "khion" ]`** — the user lives exactly there; claiming them under lumi is [impossible](../explanation/the-three-outcomes.md#2-impossible--loud-error).
- **`hosts = []`** — known to live on *no* host; any host co-claim fails.

den never produces the unknown case, so this only comes up standalone. See [roster and the den boundary](../explanation/roster-and-den-boundary.md#the-null-vs--split).

## The lower-level entry

`mkResolve`/`mkResolveSystem` are the author-facing doors and take self-labeling units. If you want the engine directly — a hand-built claim-tree unit, a custom merge — use `resolveWith { roster, ctx, merge ? ... } unit` from [`resolve.nix`](../../../modules/_lib/ownerships/resolve.nix). It's the same engine without the surface translator. Signatures for all of these are in [doors and `program` args](../reference/doors-and-program-args.md).

## See also

- [Roster and the den boundary](../explanation/roster-and-den-boundary.md) — the two backends and the null/`[]` split.
- [Roster shape](../reference/roster-shape.md) — what `toRoster` produces.
- [Doors and `program` args](../reference/doors-and-program-args.md) — `mkResolve`, `mkResolveSystem`, `resolveWith`, `define`, `toRoster`.
