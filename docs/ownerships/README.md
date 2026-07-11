# Ownerships

Ownerships is how a skadi aspect says *who a piece of config is for* — a host, a user, several of them, or everyone — right on the config itself. A unit tags itself with `hosts` / `users` / `exceptHosts` / `exceptUsers` / `when`; leave the tags off and it's owned by everyone. One call composes the tagged tree, checks it against the fleet, keeps what applies to the machine being built, and merges what's left.

It replaced the old `scoped` framework. The win is authoring: no `{ host, user }:` wrapper, no `let for = scoped.for ...`, no threading context between blocks. A unit self-labels and the resolver does the rest.

## The one-screen model

- A **unit** is a plain attrset. Anything on it that isn't a claim key is config; `children` nests one unit under another.
- The **claim keys** are `hosts`, `users`, `exceptHosts`, `exceptUsers`, `when`. None of them set = **globally owned**. That's the default, not a special case.
- A child claim can only ever **narrow** its parent, never widen it. A disjoint nest is a contradiction, caught loudly.
- Resolving a tree has exactly **three outcomes**: a unit that doesn't apply to this build is silently **inactive**; a claim that can never be satisfied is a loud **impossible** error; two co-owners setting the same scalar differently is a loud **conflict** error. Nothing else errors.
- Aspects don't call the resolver directly. They author through **`program`** — the packages/files/templates front door — which forwards the same claim keys into the surface underneath.

The whole thing in one real aspect. `kitty` claims nothing, so it's global and needs no wrapper:

```nix
den.aspects.kitty = program {
  pkg = pkgs: pkgs.kitty;
  files = [
    { dest = ".config/kitty/kitty.conf"; src = "${rootPath}/configs/kitty/kitty.conf"; }
  ];
};
```

## Find your way around

Three tiers, split by what you're trying to do.

**Understand it** — [explanation/](explanation/):

- [The authoring surface](explanation/authoring-surface.md) — units, claim keys, why untagged is the default.
- [The two doors and `program`](explanation/doors-and-program.md) — user scope vs host-only, and the front door aspects actually use.
- [The three outcomes](explanation/the-three-outcomes.md) — inactive, impossible, conflict.
- [Engine internals](explanation/engine-internals.md) — the pipeline, the axis model, merge.
- [Roster and the den boundary](explanation/roster-and-den-boundary.md) — where fleet data comes from, and running with no den.

**Do a task** — [how-to/](how-to/):

- [Make an aspect host-only](how-to/host-only-aspect.md)
- [Own by everyone except some hosts/users](how-to/own-by-all-except.md)
- [Narrow a single field](how-to/narrow-a-single-field.md)
- [Gate on a predicate with `when`](how-to/predicate-with-when.md)
- [Run standalone without den](how-to/run-standalone-without-den.md)
- [Add a new axis](how-to/add-a-new-axis.md) *(advanced)*

**Look something up** — [reference/](reference/):

- [Claim keys](reference/claim-keys.md)
- [Doors and `program` args](reference/doors-and-program-args.md)
- [Error catalog](reference/errors.md)
- [Roster shape](reference/roster-shape.md)
- [Glossary](reference/glossary.md)

## Source map

The code lives under `modules/_lib/ownerships/`, plus the `program` front door and the den adapter next door. Every page links to its backing file; the canonical paths, from here:

| File | What it holds |
| --- | --- |
| [`engine.nix`](../../modules/_lib/ownerships/engine.nix) | The pure pipeline: compose, check, assertCtx, select, merge |
| [`axes.nix`](../../modules/_lib/ownerships/axes.nix) | Polarity-set type, host + user axes, the `when` axis, membership check |
| [`merge.nix`](../../modules/_lib/ownerships/merge.nix) | List strategies + conflict policy |
| [`resolve.nix`](../../modules/_lib/ownerships/resolve.nix) | Roster → registry + checks; the standalone `resolveWith` entry |
| [`surface.nix`](../../modules/_lib/ownerships/surface.nix) | The author-facing translator + the two doors |
| [`roster.nix`](../../modules/_lib/ownerships/roster.nix) | Roster shape + the den-free `define.*` backend |
| [`../program.nix`](../../modules/_lib/program.nix) | The packages/files/templates front door |
| [`../den.nix`](../../modules/_lib/den.nix) | The one den-internals boundary (the roster adapter) |
