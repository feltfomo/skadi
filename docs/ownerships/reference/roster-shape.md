# Roster shape reference

The fleet data the engine resolves against. Every axis's `satisfiable`, `select`, and the membership check read from this one structure. Backing: [`roster.nix`](../../../modules/_lib/ownerships/roster.nix) (shape + standalone backend), [`resolve.nix`](../../../modules/_lib/ownerships/resolve.nix) (`engineArgsFor`), [`../den.nix`](../../../modules/_lib/den.nix) (den adapter).

## The shape

```nix
{
  hosts;                       # [ hostName ]
  users;                       # [ userName ]
  membership;                  # { <hostName> = [ userName ]; ... }
  usersWithUnknownMembership;  # [ userName ]
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `hosts` | `[ string ]` | Every host name in the fleet. `satisfiable`/`select` for the host axis materialize against this. |
| `users` | `[ string ]` | Every user name in the fleet. Same, for the user axis. |
| `membership` | `{ host = [ user ]; }` | Which users live on which host. The membership check reads this. |
| `usersWithUnknownMembership` | `[ string ]` | Users whose host membership is unknown; the membership check lets them through under any host. |

## Two backends produce it

### den adapter — `modules/_lib/den.nix`

Reads `den.hosts.<system>.<host>.users` off den's public entity surface and shapes it into a roster. This is the **only** file permitted to touch den internals — keep den access here. den always knows which users live where, so `usersWithUnknownMembership` is always `[]` from this backend.

### standalone — `define.*` + `toRoster` (`roster.nix`)

Builds the same shape with no den:

- `define.host name` — adds a host.
- `define.user name { hosts ? null }` — adds a user and records membership.
- `toRoster [ decls ]` — folds declarations into the roster.

## The `hosts` argument to `define.user`

This is the one semantic subtlety, and it only arises standalone (den never emits the unknown case):

| Value | Meaning | Membership check |
| --- | --- | --- |
| `null` (default) | Membership **unknown** | User is placed in `usersWithUnknownMembership`; let through under any host. |
| `[ "khion" ]` | Lives on those hosts | Claiming them under any other host is [impossible](../explanation/the-three-outcomes.md#2-impossible--loud-error). |
| `[]` | Lives on **no** host | Any host co-claim fails the membership check. |

`null` degrades gracefully to same-axis-only checking; `[]` is a real, enforced "nowhere." Don't conflate them.

## See also

- [Roster and the den boundary](../explanation/roster-and-den-boundary.md) — the narrative, and why den is the only internals touchpoint.
- [Run standalone without den](../how-to/run-standalone-without-den.md) — building a roster by hand.
- [Doors and `program` args](doors-and-program-args.md) — `define` / `toRoster` / `engineArgsFor` signatures.
