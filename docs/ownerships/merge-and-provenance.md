# Merge, profiles, locks, and provenance

Ownerships merges selected plain values by shape. The tracked merge is the single recursive implementation used by ordinary values, diagnostics, profiles, locks, and provenance.

## Default rules

The built-in `strict-ordered` behavior is:

- attrsets deep-merge by key;
- lists concatenate in source order;
- equal scalar values retain the first value;
- differing scalar values conflict;
- equal derivations compare by `outPath`;
- functions are always unequal.

Lists are terminal nodes. Their strategy owns the list as a whole, so provenance does not invent per-element ownership.

## Tracked entries

```nix
{
  value = { services.example.enable = true; };
  contributor = {
    identity = "unit 'example'";
    owners = { ...effective claims... };
    mergeProfile = "strict-ordered";
  };
}
```

The result is:

```nix
{
  value = { ...merged value... };
  provenance = {
    path = "";
    contributors = [ ... ];
    children.services.children.example = ...;
  };
}
```

Ordinary resolution projects `.value`. Provenance is constructed lazily alongside it.

## Built-in list strategies

| Name | Behavior |
| --- | --- |
| `ordered-concat` | Append right to left in source order. |
| `dedup-union` | Append and retain the first occurrence of each equal item. |
| `take-right` | Replace the left list with the right list. |

Unprofiled low-level callers can choose a strategy per path with `listStrategyFor`.

## Built-in profiles

### `strict-ordered`

```nix
{
  listStrategy = "ordered-concat";
  scalarPolicy = strictScalar;
  attrsetTreatment = "deep";
}
```

### `last-wins`

```nix
{
  listStrategy = "take-right";
  scalarPolicy = takeRightScalar;
  attrsetTreatment = "take-right";
}
```

Use `last-wins` sparingly. It deliberately suppresses disagreement.

## Profile selection

At a merge path:

1. a non-null `profileForPath path` wins;
1. otherwise a unanimous explicit contributor profile wins;
1. otherwise `strict-ordered` is used where disagreement rules allow it.

Different explicit profiles conflict for scalars. Mixing explicit and default profiles conflicts for list or overlapping attrset decisions that require one coherent treatment. A path profile overrides unit disagreement at that path.

A parent profile does not inherit into child contributors.

## Profile validation and laziness

Profiled surface constructors validate authored profile names on every unit, including inactive units.

The merge layer validates an activated profile record before using it:

- profile name is a string;
- profile value is an attrset;
- `listStrategy` is a string naming a registered function;
- `scalarPolicy` is a function;
- `attrsetTreatment` is `deep` or `take-right`.

Unused profile registrations remain lazy. This permits optional or generated registries without forcing every entry during an unrelated resolve.

## Custom profiles

```nix
let
  profiles = ownershipsMerge.builtinProfiles // {
    union-lists = {
      listStrategy = "dedup-union";
      scalarPolicy = ownershipsMerge.strictScalar;
      attrsetTreatment = "deep";
    };
  };

  resolveProfiled = ownerships.mkResolveProfiled {
    inherit profiles;
  } roster;
in
resolveProfiled [
  {
    mergeProfile = "union-lists";
    packages = [ "a" "b" ];
  }
  {
    mergeProfile = "union-lists";
    packages = [ "b" "c" ];
  }
] ctx
```

The public facade intentionally exposes profiled resolver constructors, not the internal merge module. Custom merge work is an advanced library concern.

## Single-writer locks

`mkMerge` accepts:

```nix
lockFor = path:
  if path == "services.example" || lib.hasPrefix "services.example." path then
    contributor: contributor.identity == "unit 'owner'"
  else
    null;
```

Authorization runs before shape dispatch and scalar equality. A foreign contributor violates a lock even if it writes an equal value.

Locks are path-local. A subtree policy must explicitly match descendants.

With no `lockFor` argument, a single-contributor attrset can be adopted without walking all descendants. Opting into locks requires descendant inspection so nested writes cannot bypass authorization.

## Provenance interpretation

A provenance node answers which selected leaves reached that value path. It does not mean one contributor exclusively owns the resulting semantic option.

For lists, contributors own the merged list node. For attrsets, child provenance narrows to contributors that supplied each branch. For terminal conflicts, diagnostics use safe contributor identity and never render the differing values.

Use trace merge provenance for post-merge attribution. The trace's `preMergeContribution.offeredPaths` answers only which top-level paths a selected leaf offered before merge.
