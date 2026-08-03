# Ownerships reference

## Unit grammar

```nix
{
  # optional claims
  hosts = [ ... ];
  exceptHosts = [ ... ];
  users = [ ... ];
  exceptUsers = [ ... ];
  when = ctx: true;

  # optional metadata
  label = "...";
  source = "...";
  mergeProfile = "...";

  # payload, choose one form
  services.example.enable = true;
  # or: value = { ... };

  # optional descendants
  children = [ ... ];
}
```

`label`, `source`, and `mergeProfile` do not inherit. Claims do inherit through narrowing.

## Public facade

All functions are exported from `modules/_lib/ownerships/default.nix`.

| Function | Result |
| --- | --- |
| `mkResolve roster units ctx` | User-scope merged value. |
| `mkResolveSystem roster units ctx` | System-scope merged value. |
| `mkResolveTrace roster units ctx` | User value, decisions, stages, and provenance. |
| `mkResolveSystemTrace roster units ctx` | System trace. |
| `mkResolveMatrix roster { units; contextFor ? ...; }` | User fleet projection. |
| `mkResolveSystemMatrix roster { units; contextFor ? ...; }` | System fleet projection. |
| `mkResolveStrict roster units ctx` | User resolve after roster-validating the context. |
| `mkResolveSystemStrict roster units ctx` | System strict resolve. |
| `mkResolveProfiled args roster units ctx` | User resolve with merge profiles enabled. |
| `mkResolveSystemProfiled args roster units ctx` | System profiled resolve. |
| `translate unit` | Translate author syntax to engine grammar. |
| `claimKeys` | Ordered public claim-key list. |
| `define.<axis>` | Standalone declaration constructor. |
| `toRoster declarations` | Project the default descriptor roster. |
| `mkRoster descriptors` | Construct a custom descriptor-driven roster facade. |
| `importUnits { dir; args ? { }; }` | Recursively import one unit collection. |
| `importUnitSets { dir; args ? { }; }` | Import optional `system` and `home` collections from one tree. |

The first argument set is curried. For example:

```nix
resolve = ownerships.mkResolve roster;
value = resolve units ctx;
```

## Unit import helpers

### `importUnits`

```nix
units = ownerships.importUnits {
  dir = ./units;
  args = { inherit pkgs; };
};
```

Behavior:

- recursively visits directories;
- imports regular files ending in `.nix`;
- ignores regular non-Nix files;
- rejects symlink and unknown filesystem entry types;
- sorts files by relative path before import;
- calls function files with `args`;
- accepts one unit attrset or a list of unit attrsets from each file;
- flattens all results into one list;
- rejects non-attrset results with the relative source path;
- validates the outer unit shell without forcing payload fields.

The helper does not assign a scope. Pass the resulting list to the appropriate user or system resolver.

### `importUnitSets`

```nix
unitSets = ownerships.importUnitSets {
  dir = ./units;
  args = { inherit pkgs; };
};
```

The root may contain `system`, `home`, or both as directories. The result always has both keys; a missing collection is an empty list:

```nix
{
  system = [ ... ];
  home = [ ... ];
}
```

At the mixed-tree root:

- loose `.nix` files are rejected as unclassifiable;
- directories other than `system` and `home` are rejected;
- `system` or `home` entries that are not directories are rejected;
- regular non-Nix files are ignored;
- unsupported filesystem entry types are rejected.

Each recognized collection uses the same recursive behavior and ordering as `importUnits`.

## Current public claim keys

In stable validation order:

```nix
[
  "hosts"
  "users"
  "exceptHosts"
  "exceptUsers"
  "when"
]
```

Custom descriptor surfaces may append keys without changing the production default.

## Scope rules

| Axis | User scope | System scope | Context key |
| --- | --- | --- | --- |
| host | yes | yes | `host` |
| user | yes | no | `user` |
| when | yes | yes | none |

System scope recursively rejects forbidden keys before engine selection.

## Built-in merge values

List strategies:

- `ordered-concat`
- `dedup-union`
- `take-right`

Profiles:

- `strict-ordered`
- `last-wins`

Attrset treatments:

- `deep`
- `take-right`

Conflict policies are functions receiving `path`, left tracked node, and right tracked node.

## Stage API

Leaf stage:

```nix
{
  view = "leaf";
  run = registry: leaf: diagnostics;
}
```

Tree stage:

```nix
{
  view = "tree";
  run = { registry, leaves }: diagnostics;
}
```

Survivor stage:

```nix
{
  view = "survivors";
  run = { registry, ctx, survivors }: diagnostics;
}
```

Diagnostics use domain records that the engine converts to Krisis diagnostics. Common fields are `kind`, `unit`, `label`, `source`, `axis` or `axes`, `claims`, and `reason`.

## Error classes

### Author shape

- unit is not an attrset;
- malformed claim value;
- both polarities on one axis;
- malformed children, value, label, source, or profile;
- `value` mixed with inline payload;
- forbidden scope key.

### Impossible declaration

- unknown member;
- disjoint nested claim;
- empty include;
- ambiguous alias;
- no compatible pair for a registered relation.

### Context

A narrowed axis has a non-null `ctxKey`, but the build context supplies no entity.

Strict doors additionally reject unknown or incompatible supplied contexts even when authored claims are global.

### Merge

- differing strict scalar values;
- foreign write beneath a lock;
- unknown or malformed strategy;
- unknown or malformed activated profile;
- incompatible contributor profiles.

### Stage

Unknown view, malformed callback, or a stage-produced structured diagnostic.

### Unit import

- non-attrset `args`;
- imported file returns neither a unit attrset nor a list of unit attrsets;
- unsafe filesystem entry type;
- mixed tree has a loose root `.nix` file;
- mixed tree has an unknown top-level directory;
- mixed tree has no `system` or `home` directory.

## Glossary

- **unit**: author attrset containing payload and optional ownership metadata;
- **claim**: restriction along registered axes;
- **axis**: implementation of one ownership dimension;
- **descriptor**: author, context, scope, axis, and roster metadata for an axis;
- **top/global**: the identity claim that selects everyone;
- **narrow/meet**: combine parent and child claims without widening;
- **leaf**: config-bearing composed node with effective claim;
- **stage**: validation callback at a pipeline boundary;
- **relation**: compatibility rule between two axes;
- **roster**: canonical members, aliases, membership, dimensions, and display data;
- **context**: concrete entities for one resolve;
- **survivor**: selected leaf after context matching;
- **contributor**: survivor identity and effective owners carried to merge;
- **provenance**: path-aligned contributor tree;
- **matrix**: structural selection report across modeled contexts.

## Lower-level seams

`resolve.nix` exports `resolveWith`, `engineArgsFor`, and `validateRosterCtx`. `engine.nix`, `axes.nix`, `merge.nix`, and `matrix.nix` export additional focused seams for tests and subsystem composition.

These are not ordinary aspect APIs. Preserve facade behavior when changing them, and add parity and forcing tests around any new seam.
