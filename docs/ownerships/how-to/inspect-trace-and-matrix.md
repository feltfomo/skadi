# Inspect a trace or matrix

## One context

Swap the ordinary door for its trace sibling:

```nix
trace = ownerships.mkResolveTrace roster units ctx;
```

Inspect `trace.trace` to answer which axis rejected a leaf. Inspect `trace.mergeProvenance` to answer which surviving contributors reached a merged path.

System scope uses `mkResolveSystemTrace`.

## Whole fleet

```nix
matrix = ownerships.mkResolveMatrix roster { inherit units; };
```

Useful fields:

- `byContext`: survivors and inactive leaves per canonical context key;
- `dead`: impossible leaves and reasons;
- `indeterminate`: claims involving users with unknown host membership;
- `neverSelectedInModeledContexts`: valid but dormant leaves;
- `coverage.units`: contexts selecting each snapshot leaf;
- `coverage.preMerge.paths`: contexts receiving each offered top-level path;
- `hostDiffs`: pairwise unit and path differences.

For predicates that read more than entity names, pass a `contextFor` callback that enriches each generated context. Matrix output remains structural; raw config values aren't included.
