# Claim keys reference

The complete set of keys a unit reads as ownership. Everything else on a unit is config. Backing: [`surface.nix`](../../../modules/_lib/ownerships/surface.nix) (the translator + reserved-key set) and [`axes.nix`](../../../modules/_lib/ownerships/axes.nix) (the axis semantics).

## The keys

| Key | Axis | Value | Meaning |
| --- | --- | --- | --- |
| `hosts` | host | `[ hostName ]` | Owned by exactly these hosts (`include`). |
| `exceptHosts` | host | `[ hostName ]` | Owned by every host *except* these (`exclude`). |
| `users` | user | `[ userName ]` | Owned by exactly these users (`include`). User scope only. |
| `exceptUsers` | user | `[ userName ]` | Owned by every user *except* these (`exclude`). User scope only. |
| `when` | predicate | `ctx: bool` | Owned where the predicate holds. Select-only. |
| `children` | — | `[ unit ]` | Nests units; each child narrows this unit. Not itself a claim. |

**Reserved keys** = the five claim keys plus `children`. A reserved key can't double as a config path on the same unit; see [errors](errors.md#author-time-surface).

## Value rules

- **Name lists** (`hosts`/`users`/`exceptHosts`/`exceptUsers`) must be lists of strings. A non-list throws at author time.
- **A unit sets at most one polarity per axis.** `hosts` *and* `exceptHosts` together (or `users` + `exceptUsers`) throws — pick the set or its complement.
- **`when`** must be a function of the build context. It receives `{ host, user }` at user scope, `{ host }` host-only.
- **Empty positive** `hosts = []` is `include []` — the empty set, i.e. [impossible](../explanation/the-three-outcomes.md#2-impossible--loud-error) on its own.
- **Empty negative** `exceptHosts = []` is `exclude []` — the identity, i.e. *global* (equivalent to omitting the key).

## Untagged = global

Omitting an axis's keys means that axis is `top` (global) for the unit. Omitting all of them means the unit is globally owned everywhere — the default. This isn't a sentinel value; it's the identity claim on each axis. See [the authoring surface](../explanation/authoring-surface.md#untagged-means-global--the-default-not-a-special-case).

## Scope restriction

`users` / `exceptUsers` are only valid where the resolve carries a user (user scope). In a host-only resolve (`resolveSystem`, or `program`'s `nixos` path) any user claim throws at author time — a host-wide slice binds no user. See [`assertNoUserClaim`](errors.md#author-time-surface).

## See also

- [The authoring surface](../explanation/authoring-surface.md) — the model behind the keys.
- [Own by everyone except…](../how-to/own-by-all-except.md) — the negative keys in practice.
- [Error catalog](errors.md) — what each malformed claim throws.
