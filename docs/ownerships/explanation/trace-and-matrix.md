# Trace and fleet matrix

Trace and matrix are read-only projections of the real resolver. Neither reimplements claim semantics.

## Trace

`mkResolveTrace` and `mkResolveSystemTrace` use the same translated tree, stages, context checks, selection, and merge as ordinary resolve. The result includes:

- `value`, identical to ordinary resolve;
- one trace record per leaf;
- per-axis claim, observed details, and select decision;
- rejecting axes;
- check results and context requirements;
- pre-merge top-level paths offered by selected leaves;
- lazy merge provenance;
- stage reports.

The pre-merge path list says what a leaf offered, not who owns the post-merge result. Post-merge attribution lives in `mergeProvenance`.

## Fleet matrix

`mkResolveMatrix` evaluates selection across every known host/user membership pair. `mkResolveSystemMatrix` uses one context per host. Reports contain stable `leaf-N` snapshot keys, identities, shallow shapes, selections, top-level pre-merge coverage, and pairwise host diffs.

The matrix separates:

- `dead`: engine-proven impossible leaves;
- `neverSelectedInModeledContexts`: valid leaves rejected in every modeled row;
- `indeterminate`: user claims that might select on hosts hidden by unknown membership.

A `when` predicate that returns false everywhere is dormant, not dead. Predicates have no finite roster domain that can prove impossibility.

## Safety boundary

Reports never export raw config payloads. Package and secret-backed values are represented by identity, attribute names, or derivation name. If a new report needs more detail, keep it structural unless the caller explicitly opts into forcing values.
