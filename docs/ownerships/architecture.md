# Ownerships architecture

Ownerships is descriptor-driven at the author and roster boundaries and axis-agnostic in the engine.

## Pipeline

```text
translate
→ compose
→ leaf stages
→ tree stages
→ context demand
→ selection
→ survivor stages
→ contributor projection
→ merge
```

Each diagnostic phase fully aggregates its diagnostics before throwing. A failed earlier phase prevents later phases from evaluating.

## Translation

`surface.nix` converts self-labeling units into the engine grammar:

```nix
{
  hosts = [ "khion" ];
  label = "example";
  services.example.enable = true;
}
```

becomes conceptually:

```nix
{
  claim.host = include [ "khion" ];
  label = "example";
  value.services.example.enable = true;
}
```

The surface validates reserved-key shape, recursive scope restrictions, `value` exclusivity, and profiled-door names. It contains no claim algebra or selection logic.

## Descriptor compilation

`axes.compileDescriptors` validates a descriptor set once and projects:

- ordered descriptors;
- ordered author-key metadata;
- public claim keys;
- descriptors with roster projection.

Surface validation, registry construction, and roster construction reuse this compiled metadata instead of repeatedly rediscovering it.

A descriptor owns:

- axis name and implementation;
- author keys, ordering, shape validation, and parsing;
- allowed scopes and scope-specific errors;
- context claim and label projection;
- optional declaration constructor and roster projector;
- optional leaf stages.

The production descriptors are `host`, `user`, and `when`.

## Compose

`engine.compose` walks the translated tree. At each node it narrows the parent's effective claim with the node's own claim on every registered axis.

Each config-bearing node produces one leaf containing:

- effective claim;
- opaque payload;
- optional label and source;
- optional merge profile.

Nodes without payload may scope descendants. Identity and merge profile do not inherit.

## Stages

Stages have one of three views:

```nix
{
  view = "leaf" | "tree" | "survivors";
  run = ...;
}
```

Unknown views or missing callbacks throw.

### Leaf stages

Run one rule over one composed leaf. Production order is:

1. ambiguous alias validation;
1. per-axis satisfiability;
1. registered cross-axis relations;
1. descriptor-contributed leaf stages.

Diagnostics flatten in stage order, then leaf order.

### Tree stages

Receive `{ registry; leaves; }` after leaf validation and before context demand. They express whole-declaration invariants independent of the current build.

### Survivor stages

Receive `{ registry; ctx; survivors; }` after selection. They express current-build coverage such as requiring exactly one selected provider.

## Context demand and selection

A set axis with a non-global claim requires the entity named by its `ctxKey`. Global claims short-circuit selection and do not read the context entity.

This is why an untagged unit can resolve without host or user values. Missing context is an error only when an authored claim actually narrows that axis.

`selectPrepared` is the shared boundary used by ordinary resolution and matrix projection. It performs:

1. context-demand validation;
1. per-axis selection;
1. survivor-stage execution;
1. selection, context, and survivor traces.

Keeping this boundary shared prevents matrix behavior from drifting from real resolution.

## Contributor projection and merge

Selected leaves become tracked entries. Each contributor carries:

- safe identity;
- opaque effective owners;
- optional merge profile.

The merge layer interprets value shape and merge policy, never ownership semantics. Ordinary resolve projects only the merged value. Trace callers can inspect the lazy provenance sibling.

## Plain and diagnostic projections

- Plain resolve returns only the merged value.
- Trace runs the same full pipeline and exposes decisions and provenance.
- Matrix uses compose, leaf stages, tree stages, context demand, selection, and survivor stages, but deliberately does not merge payloads.
- Strict resolve additionally validates the supplied context tuple against the roster.
- Profiled resolve activates merge-profile semantics and validation.

## Laziness boundaries

Ownerships must preserve:

- inactive payloads are never merged;
- safe identity does not serialize arbitrary payloads;
- ordinary resolve does not force trace details;
- merge provenance remains lazy unless inspected or required by locks/profiles;
- unused merge-profile registrations remain lazy;
- matrix reports expose only identity, shallow shape, claims, decisions, and path names.

## Extending the pipeline

Add a descriptor for new axis vocabulary. Add relation data for cross-axis compatibility. Add a stage only when an invariant belongs to an existing pipeline boundary.

Do not teach the engine a new axis name. Do not implement alternate selection in matrix or trace. Do not add a merged-output stage until a real invariant requires that boundary and its safe data contract is defined.
