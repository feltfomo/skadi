# Doors and `program` args reference

Signatures for the resolve entry points and the `program` spec. Backing: [`surface.nix`](../../../modules/_lib/ownerships/surface.nix), [`resolve.nix`](../../../modules/_lib/ownerships/resolve.nix), [`roster.nix`](../../../modules/_lib/ownerships/roster.nix), and [`../program.nix`](../../../modules/_lib/program.nix).

## The two doors

Each is built once from a roster, then called with a unit list and a context.

### `mkResolve roster`

```
mkResolve :: roster -> [ unit ] -> { host, user, ... } -> merged
```

User-scope door. Translates self-labeling units, resolves against a context carrying both `host` and `user`. Units may claim on `users` / `exceptUsers`.

### `mkResolveSystem roster`

```
mkResolveSystem :: roster -> [ unit ] -> { host, ... } -> merged
```

Host-only door. Context carries `host`, no user (user pinned out). Eagerly asserts no unit in the tree carries a user claim (see [`assertNoUserClaim`](errors.md#author-time-surface)) before resolving.

### `resolveWith` (lower-level, standalone)

```
resolveWith :: { roster, ctx, merge ? <default> } -> unit -> merged
```

The engine entry without the surface translator, from [`resolve.nix`](../../../modules/_lib/ownerships/resolve.nix). Takes a single claim-tree unit and an explicit context. Use it for tests or a custom merge; see [run standalone without den](../how-to/run-standalone-without-den.md).

### Roster construction

- `define.host name` — declare a host.
- `define.user name { hosts ? null }` — declare a user; `hosts` is where they live (`null` = unknown, `[]` = nowhere). See [roster shape](roster-shape.md).
- `toRoster [ decls ]` — fold declarations into a roster.
- `engineArgsFor roster` — build the axis registry + checks from a roster (used internally by the doors).

## `program` spec

`program` (bound to the roster and handed to aspects as a module arg) takes one spec attrset. All fields optional.

| Field | Shape | Scope | Notes |
| --- | --- | --- | --- |
| `pkg` | `pkgs: package` | user (home) | Added to `home.packages` if it survives selection. |
| `imports` | `[ module ]` | user (home) | home-manager imports. One leaf; no per-entry claim. |
| `files` | `[ { dest; src; <claim keys> } ]` | user (home) | hjem file links (`${dest}.source = src`). Per-entry claims narrow a single link. |
| `templates` | `[ { name; templateFile; subdir ? ; <claim keys> } ]` | user (home) | noctalia templates, written via a home activation step. Per-entry claims allowed. |
| `noctaliaConfig` | attrset | user (home) | Serialized to TOML and linked under `.config/noctalia/`. |
| `nixos` | `{ pkgs, config, ... }: [ unit ]` | host-only | Returns its own claimed units; resolved through `mkResolveSystem`. |
| *(claim keys)* | `hosts` / `users` / `exceptHosts` / `exceptUsers` / `when` | — | Narrow the **home** slices as a whole. See below. |

### How `program` forwards claims

`program` splits the spec into two independent resolves:

- **Home slices** (`pkg`, `imports`, `files`, `templates`, `noctaliaConfig`) become one unit tree resolved at **user scope**. Spec-level claim keys sit on that tree's root, narrowing every home field at once; per-entry claim keys on a `files` / `templates` entry narrow just that entry.
- **The nixos slice** is resolved **host-only** and *separately*. `spec.nixos` is called as `spec.nixos { inherit pkgs config; }` — `pkgs` and `config` are threaded in — and must return a list of units. **Spec-level claim keys do not reach `spec.nixos`;** those units carry their own claims.

Consequence to remember: a top-level claim on a `program` spec narrows the home slices only. A host-only nixos unit repeats its own host claim (this is why `hyprland` states `hosts` both at the top and inside its `nixos` unit). See [where the claims land](../explanation/doors-and-program.md#where-the-claims-land).

`program` reads `host` (and, for home, `user`) lazily from each generated class module's own args, so the call site stays a bare `program { ... }` with no context wrapper. An untagged spec reads no context at all.

## See also

- [The two doors and `program`](../explanation/doors-and-program.md) — the narrative version.
- [Run standalone without den](../how-to/run-standalone-without-den.md) — `mkResolve` / `resolveWith` / `define` in use.
- [Roster shape](roster-shape.md) — what the doors are bound against.
- [Error catalog](errors.md) — the host-only user-claim assert.
