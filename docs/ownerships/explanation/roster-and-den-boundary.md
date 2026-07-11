# The roster, and the den boundary

The engine's `satisfiable`, `select`, and membership check all need to know what the fleet actually contains — which hosts and users exist, and who lives where. That data is the **roster**, and it's the one place den touches ownerships.

## The roster shape

A roster is exactly:

```nix
{ hosts; users; membership; usersWithUnknownMembership }
```

- `hosts` / `users` — name lists.
- `membership` — host → `[ user ]`.
- `usersWithUnknownMembership` — users declared without any host (see the null-vs-`[]` split below).

[`resolve.nix`](../../../modules/_lib/ownerships/resolve.nix)'s `engineArgsFor` builds the axis registry and the membership check from this one shape. Neither the engine nor the axes know or care which backend produced it. The exact field semantics are in [roster shape](../reference/roster-shape.md).

## Two backends, same shape

**den** — the adapter in [`modules/_lib/den.nix`](../../../modules/_lib/den.nix) reads `den.hosts.<system>.<host>.users` straight off den's public entity surface and shapes it into a roster. This is what every aspect in skadi is bound against. `den.nix` is the *one file allowed to touch den internals* — keep any den access there and nowhere else. Because den always knows which users live on which host, its `usersWithUnknownMembership` is always empty.

**Standalone** — [`roster.nix`](../../../modules/_lib/ownerships/roster.nix)'s `define.*` + `toRoster` build the same shape with no den present. This is what makes ownerships den-independent: the pure files (`engine`, `axes`, `merge`, `roster`, `surface`) resolve on their own, and den is only ever behind the `den.nix` adapter. Walking it is [run standalone without den](../how-to/run-standalone-without-den.md).

## The null-vs-`[]` split

The only behavioral difference between the backends is how they express "I don't know where this user lives." In the standalone `define.user`:

- `hosts = null` (the default) means **unknown** — the membership check lets this user through anywhere. This is the degrade-to-same-axis-only path, and it's why a standalone user who never named their hosts doesn't trip a false membership error.
- `hosts = []` means **known to live on no host** — a real membership failure if something claims that user under a host.

den never produces the unknown case (it always knows membership), so this split only matters standalone. The membership check reads `usersWithUnknownMembership` to implement the rescue.

## See also

- [Roster shape](../reference/roster-shape.md) — the field-by-field reference.
- [Run standalone without den](../how-to/run-standalone-without-den.md) — build a roster and resolve with no den.
- [Engine internals](engine-internals.md) — where `satisfiable`, `select`, and membership consume the roster.
