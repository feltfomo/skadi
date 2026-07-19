# Merge, provenance, locks, and profiles

Ownerships merges the selected plain values by shape. It does not reproduce NixOS option-type merging.

## Shape rules

- Attrsets deep-merge by key.
- Lists use a named list strategy.
- Scalars use a scalar policy.

The default profile is `strict-ordered`: lists append in source order, attrsets recurse, equal scalars survive, and differing scalars conflict.

Built-in list strategies are `ordered-concat`, `dedup-union`, and `take-right`. Built-in profiles are:

- `strict-ordered`: deep attrsets, ordered lists, strict scalars;
- `last-wins`: right-hand attrsets/lists/scalars win at a colliding node.

## Tracked merge

`mergeTracked` is the only shape recursion on the resolver path. Every node has lazy provenance:

```nix
{
  path = "services.foo";
  contributors = [ { identity; owners; } ... ];
  children = { ... };
}
```

Lists are terminal. Their strategy owns the list as a whole, so provenance doesn't pretend to know per-element ownership.

Ordinary resolve projects only `.value`. Contributor identity, owners, and provenance stay unforced unless a conflict, lock, profile decision, or trace needs them.

## Single-writer locks

`mkMerge { lockFor = path: ...; }` opts into path authorization. `lockFor` returns either `null` or a predicate over a contributor. Authorization runs before shape dispatch and scalar equality, so an equal foreign write still violates a lock.

Subtree policies must match descendants explicitly, for example `path == "services.foo" || lib.hasPrefix "services.foo." path`.

## Merge profiles

Profiled doors validate `mergeProfile` on every authored unit, including inactive ones. Profile selection at a merge node is:

1. `profileForPath path`, when non-null;
2. a unanimous explicit unit profile;
3. `strict-ordered`.

Different explicit unit profiles on one scalar conflict. A mix of explicit and default profiles conflicts where list/attrset treatment needs one coherent decision. A path profile overrides unit disagreement at that path.

Profiles belong to config-bearing leaves and do not inherit through a parent that only scopes children.

Use `last-wins` sparingly. It can hide co-owner disagreement by design.
