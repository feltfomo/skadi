# Trace and matrix inspection

Trace and matrix are read-only projections of the same resolver machinery. They must not become alternate implementations of ownership semantics.

## One-context trace

```nix
trace = ownerships.mkResolveTrace roster units ctx;
```

System scope uses `mkResolveSystemTrace`.

The result includes:

- `value`, identical to ordinary resolution;
- one selection record per composed leaf;
- effective claims and per-axis decisions;
- rejecting axes;
- leaf-check and context-demand results;
- pre-merge contribution shape and top-level paths;
- stage reports;
- lazy merge provenance.

### Selection records

A leaf record identifies:

- safe unit identity;
- effective claim;
- each axis's claim, observed details, and decision;
- whether the leaf selected;
- axes that rejected it.

A global claim reports decision `global` without reading a context entity.

### Pre-merge versus post-merge

`preMergeContribution.offeredPaths` shows what a selected leaf offered before merge. It does not identify the owner of the final value.

Use `mergeProvenance` for path-aligned post-merge contributors.

### Stage reports

`stageReports` separates leaf, tree, and survivor views. A failing leaf phase also exposes lazy `diagnosticText.leaf` so tests and audit tools can inspect the exact aggregate text without switching to a different checker.

## Strict resolution

```nix
strict = ownerships.mkResolveStrict roster;
```

Ordinary resolution validates claims but only reads context entities demanded by those claims. Strict resolution first represents the supplied context as a claim and validates it against the roster and registered relations.

Use strict mode for external or audit contexts that must themselves be known. Do not use it merely to change selection behavior; successful strict resolution delegates to the same ordinary resolver.

## Fleet matrix

```nix
matrix = ownerships.mkResolveMatrix roster {
  inherit units;
};
```

System scope uses `mkResolveSystemMatrix`.

User rows are generated from known host membership. Users with unknown membership do not invent rows.

The matrix runs:

1. compose;
1. leaf-stage classification;
1. tree stages over live leaves;
1. context demand per row;
1. selection per row;
1. survivor stages per row.

It does not merge payloads or construct merge provenance.

## Matrix fields

### `units`

Stable snapshot keys such as `leaf-0` map to safe identity and shallow shape.

Keys describe position in this report, not durable source identity.

### `byContext`

Each context reports:

- canonical host and optional user name;
- survivor leaf keys;
- inactive leaf keys and rejecting axes;
- unique top-level pre-merge paths.

### `dead`

Leaves proven impossible by leaf diagnostics, with projected reasons. These include impossible same-axis claims and incompatible registered relations.

### `neverSelectedInModeledContexts`

Valid live leaves rejected in every generated row, with per-context rejecting axes.

A false-everywhere predicate belongs here rather than `dead`.

### `indeterminate`

User claims that select nowhere in modeled rows but include users whose host membership is unknown. The report cannot distinguish dormant from potentially active on an unmodeled host.

### `coverage`

`coverage.units` maps every leaf key to selecting contexts.

`coverage.preMerge.paths` maps top-level offered paths to contexts while preserving first-occurrence path order.

### `hostDiffs`

For each ordered host pair, reports left-only and right-only survivor keys and pre-merge paths. User-scope host ownership is the union across that host's modeled user rows.

## Enriched contexts

Predicates may read more than names. Supply `contextFor`:

```nix
ownerships.mkResolveMatrix roster {
  inherit units;
  contextFor = { hostName, userName }: {
    host = {
      id = hostName;
      gpu = roster.dimensions.gpu.byHost.${hostName};
    };
    user.name = userName;
  };
}
```

The callback must preserve the entity fields required by registered descriptors.

## Safety boundary

Trace can expose opaque effective claims and lazy provenance because it is tied to one real resolution. Matrix is stricter: raw payloads never cross the report boundary.

Safe reports may contain:

- labels and source strings supplied by authors;
- shallow attrset keys;
- derivation names when safely available;
- canonical roster identities;
- claim data;
- stage and selection decisions;
- path names.

They must not serialize packages, secret-backed values, function bodies, or arbitrary payload attrsets.
