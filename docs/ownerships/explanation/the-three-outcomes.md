# The three outcomes

Resolving a unit tree ends one of exactly three ways. Only two of them are errors; the third — the common one — is silent. This is the whole safety story, so it's worth internalizing before you trust ownership with anything load-bearing.

The rule underneath all three: **a claim can only narrow its parent.** A unit's effective ownership is its own claim intersected with every ancestor's (intersection within an axis, AND across axes).

## 1. Inactive — silent

The effective claim is satisfiable, but it excludes the machine being built. The unit just isn't there. No error, nothing to clean up.

`audio` claims `pavucontrol` for `khion` and `lumi`. Building any other host — the installer-test VM, `generic` — the unit drops and that host collapses to `{}` for it. That's ownership working, not failing. Its own comment says so:

```nix
# pavucontrol on the real machines only. the hosts claim drops this unit on
# any host outside it, so vm/generic (which also pull base) collapse to {}.
```

An inactive unit is the expected result of *most* claims on *most* builds. If a unit you expected isn't applying, it's almost always inactive (its claim didn't match this build), not broken.

## 2. Impossible — loud error

The effective claim can never be satisfied by any real entity in the fleet. That's a contradiction, not a silent empty, so it throws — for *everyone*, regardless of who's building, because the check runs before selection.

Three ways to get here:

- **A disjoint nest.** A `lumi`-only child under a `khion`-only parent narrows `include ["khion"]` against `include ["lumi"]`, which is `include []` — the empty set. Unsatisfiable.

  ```nix
  {
    hosts = [ "khion" ];
    children = [
      { hosts = [ "lumi" ]; programs.foo.enable = true; }  # can never apply
    ];
  }
  ```

- **An unknown name.** A typo'd host or user resolves against the roster to `include []` — the same impossible.
- **A host/user pair that can't co-exist.** A unit claimed for a user who doesn't live on the claimed host. This is the one cross-axis check.

All three surface as an *impossible* diagnostic and throw before anything is selected. The exact strings are in the [error catalog](../reference/errors.md#resolve-time).

## 3. Conflict — loud error

Two genuine co-owners both survive selection and set the same scalar to different values. Attrsets merge (union of keys), lists concatenate — only a real scalar clash between real co-owners is a conflict.

```nix
[
  { hosts = [ "khion" ]; services.notion-sync.keepWarm.enable = true; }
  { hosts = [ "khion" ]; services.notion-sync.keepWarm.enable = false; }
]
```

Both units survive on khion; merge recurses into the shared attrset down to `enable`, finds `true != false`, and throws rather than picking a winner. See [engine internals](engine-internals.md) for how merge decides shape-by-shape, and the [error catalog](../reference/errors.md#resolve-time) for the string.

## That's the whole set

Everything that isn't impossible or conflict is silent narrowing. Only contradictions and real value clashes ever error. That's what keeps ownership manageable as the fleet and the aspect set grow — you don't get a wall of warnings for every unit that simply doesn't apply here.

## See also

- [Engine internals](engine-internals.md) — the pipeline order that makes *impossible* fire for everyone and *inactive* stay silent.
- [Error catalog](../reference/errors.md) — the exact throw strings and what triggers each.
