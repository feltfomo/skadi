# Pipeline and stages

The engine is a fixed, axis-agnostic pipeline:

```text
compose -> leaf stages -> tree stages -> context demand -> select
        -> survivor stages -> merge
```

## Compose

`compose` walks the unit tree and emits one leaf for each config-bearing node. Each leaf carries its effective claim, payload, optional identity metadata, and optional merge profile.

## Leaf stages

Leaf stages run one rule over one leaf. Production registration order is:

1. ambiguous alias validation;
1. per-axis satisfiability;
1. cross-axis relations;
1. descriptor-contributed leaf stages.

Diagnostics aggregate in stage order and leaf order. An earlier phase throws before later phases evaluate.

## Tree stages

A tree stage receives `{ registry; leaves; }` before context or selection. Use it for declaration validity that must hold independently of the build being evaluated. It deliberately receives no context.

## Context demand

A context entity is required only when a leaf narrows an axis whose `ctxKey` is not null. Global claims short-circuit this demand. That's why an untagged unit can resolve with null or absent host/user values.

## Selection

For each leaf and axis:

- global claims select without reading context;
- other claims call the axis's observed selection;
- the leaf survives only when every axis selects it.

A valid miss is inactive and silent. Selection runs after declaration checks, so an impossible leaf can't hide just because the current build wouldn't select it.

## Survivor stages

A survivor stage receives `{ registry; ctx; survivors; }`. This is the right place for current-build coverage such as “exactly one bootloader survives.” An inactive leaf can't satisfy that coverage.

## Merge

Surviving leaves become tracked merge entries. Each contributor carries its identity and opaque effective owners. The engine returns only the merged value on ordinary resolve; trace callers can inspect provenance.

## Adding a stage

A stage is `{ view = "leaf" | "tree" | "survivors"; run = ...; }`. Unknown or misspelled views throw. New views should be added only when an invariant needs a new pipeline boundary.
