# Error catalog

Every throw ownerships can raise. Strings are copied verbatim from source; `${...}` marks interpolated fragments left as they appear in the code. Each entry lists the string, what triggers it, and the backing `file:function`.

Errors fall in two groups: **author-time** surface guards that fire on the shape of a unit before any resolve, and **resolve-time** diagnostics that fire during the pipeline. Resolve-time entries are ordered along the pipeline: **compose → check → assertCtx → select → merge**. (compose and select raise nothing of their own.)

## Author-time (surface)

These come from [`surface.nix`](../../../modules/_lib/ownerships/surface.nix) and fire on unit shape, independent of any build context.

### Reserved key isn't a name list

```
ownerships: '${builtins.head badList}' must be a list of names; got ${builtins.typeOf unit.${builtins.head badList}}. a reserved ownership key can't also be a config path on the same unit.
```

- **Trigger:** a unit sets `hosts` / `users` / `exceptHosts` / `exceptUsers` to something that isn't a list of names — classically a NixOS `users.*` attrset landing on the `users` claim key.
- **Backing:** `surface.nix : checkShape`.

### `when` isn't a function

```
ownerships: 'when' must be a predicate function of the build context
```

- **Trigger:** `when` set to a non-function value.
- **Backing:** `surface.nix : checkShape`.

### Both polarities on one axis

```
ownerships: a unit cannot set both '${positive}' and '${negative}' -- pick the set or its complement
```

- **Trigger:** a unit sets both `hosts` and `exceptHosts`, or both `users` and `exceptUsers`.
- **Backing:** `surface.nix : polarityFor`.

### User claim in a host-only slice

```
ownerships: a system-scope (host-only) unit sets '${builtins.head offending}' = ${lib.generators.toPretty { multiline = false; } unit.${builtins.head offending}} -- a host-only slice binds no user, so it cannot narrow on users. drop the user claim or resolve this unit at user scope.
```

- **Trigger:** a `users` / `exceptUsers` claim anywhere in a `mkResolveSystem` tree (i.e. a `program` `nixos` slice). Asserted eagerly by the host-only door before resolve.
- **Backing:** `surface.nix : assertNoUserClaim`.

## Resolve-time (engine)

Check and assertCtx diagnostics are collected and rendered together through one wrapper before throwing.

### Wrapper: rendered diagnostics

```
ownerships: ${toString (length diags)} ownership error(s):\n
```

followed by one line per diagnostic:

```
  - ${d.reason}
```

- **Trigger:** any non-empty diagnostic set from the check stage or the assertCtx stage. All `reason` strings below render through this.
- **Backing:** `engine.nix : renderDiags`.

### check — unsatisfiable claim (`reason`)

```
axis '${name}' claim can never be satisfied (disjoint nest or unknown name)
```

- **Trigger:** an axis's effective claim resolves to no member — a disjoint nest (e.g. a `lumi`-only child under a `khion`-only parent → `include []`) or an unknown/typo'd name.
- **Backing:** `engine.nix : satisfiableCheck` (an *impossible* diagnostic).

### check — host/user can't co-exist (`reason`)

```
no user in { ${us} } lives on any host in { ${hs} } -- this host/user co-ownership can never apply
```

- **Trigger:** a leaf claims both a host set and a user set with no (host, user) pair where that user lives on that host (and the user isn't marked unknown-membership). Skipped when either axis is global or a single-axis miss already covers it.
- **Backing:** `axes.nix : mkMembershipCheck` (an *impossible* diagnostic).

### assertCtx — narrowed axis with no context entity (`reason`)

```
axis '${name}' is narrowed on by claim ${lib.generators.toPretty { multiline = false; } leaf.claim.${name}} but the build ctx provides no entity for key '${registry.${name}.ctxKey}' -- only untagged (global) claims resolve without a build context
```

- **Trigger:** a leaf narrows on an axis (host/user) but the build context carries no entity for that axis's `ctxKey` — e.g. a user-narrowing claim resolved with no user in context. Global (`isTop`) claims are exempt.
- **Backing:** `engine.nix : assertCtx`.

### merge — scalar conflict

```
ownerships: conflict at ${if path == "" then "<root>" else path}: co-owners set differing values (${builtins.toJSON a} vs ${builtins.toJSON b})
```

- **Trigger:** two surviving co-owned leaves set the same scalar path to different values. Equal values merge silently; only a real clash throws.
- **Backing:** `merge.nix : strictScalar` (the default conflict policy).

### merge — missing list strategy

```
ownerships: no merge strategy '${name}' (at ${path})
```

- **Trigger:** the per-path list-strategy selector names a strategy absent from the strategy table. Unreachable with defaults (only `ordered-concat` is ever selected); reachable only via a custom `listStrategyFor` naming a strategy that doesn't exist.
- **Backing:** `merge.nix` (strategy lookup in `mergeTwo`).

## See also

- [The three outcomes](../explanation/the-three-outcomes.md) — inactive / impossible / conflict, the author's-eye view.
- [Engine internals](../explanation/engine-internals.md) — the pipeline order these fire in, and why check precedes select.
- [Claim keys](claim-keys.md) — the value rules whose violations the author-time guards catch.
