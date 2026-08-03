# Furnish architecture

Furnish separates pure evaluation from runtime mutation. The Nix compiler proves declaration shape, ownership, destination identity, collisions, executor capability, and manifest shape. The coordinator consumes the resulting manifest later.

## Module map

| File | Responsibility |
| --- | --- |
| `default.nix` | Assemble the Nix-facing facade. |
| `contract.nix` | Versions, capabilities, strategies, policies, executor identities, and manifest constructors. |
| `core.nix` | Pure compiler and validation pipeline. |
| `files.nix` | Convert selected home-relative entries into principal-aware declarations. |
| `runtime.nix` | NixOS options, native executors, manifest retention, activation, and service wiring. |
| `coordinator.nix` | One canonical Rust package derivation. |
| `tests.nix` | Pure regression, forcing, collision, and lowering proofs. |

## Pure compiler

`compile` accepts:

```nix
furnish.compile {
  declarations = [ ... ];
  executors = [ ... ];
  ctx = { host = ...; user = ...; };
  raw = { };
  provider = furnish.core.mkEnabledProvider { inherit resolve resolveSystem; };
}
```

It returns the contract projections:

- `manifestData`, the entry list;
- `manifestDocument`, the versioned document;
- `manifestJson`, its JSON representation;
- `manifestPath = null`, because store materialization belongs to `runtime.nix`;
- `raw`, passed through unchanged.

An empty declaration list is a pure no-op. It does not force ownership resolvers or executors.

## Pipeline

### 1. Shape validation

`validateShapes` aggregates structural errors across declarations. It checks labels, namespaces, authority, managed roots, destinations, representation, source shape, provenance, and conflict policy without forcing `source.value`.

Executor shape validation similarly leaves `materialize` lazy until an executor is selected.

### 2. Ownership selection

`mkEnabledProvider` wraps each declaration as an Ownerships unit. User authorities use `resolve`; system authorities use `resolveSystem`. An active unit returns its own entry, while an inactive unit resolves to an empty entry list.

Selection happens one declaration at a time. Furnish does not merge declaration payloads through Ownerships.

`offProvider` is used after Program has already selected declarations for the current principal. It accepts only untagged declarations. A remaining ownership key is a loud error because silently treating it as global would be unsafe.

### 3. Destination normalization

`deriveDestination` performs lexical normalization of `.` and `..`, resolves relative destinations beneath `managedRoot`, and requires the final destination to be a strict descendant of the root.

It then constructs:

```nix
{
  namespace = filesystemNamespace;
  destination = absoluteDestination;
  canonical = "${filesystemNamespace}:${absoluteDestination}";
}
```

No filesystem lookup is needed for this proof.

### 4. Collision indexing

Furnish groups index projections by canonical filesystem identity. More than one claimant at one identity is an error, even if both declarations would ultimately point at equal content.

Diagnostics sort claimants deterministically and include authority, declaration label, and provenance source.

`buildHostIndex` projects every declaration across every supplied principal before checking collisions. This catches cross-user and user-versus-system collisions that a per-principal compile could miss.

### 5. Executor selection

A declaration requires:

- `lifecycle-baseline`;
- the declaration's representation capability.

Enabled executors containing every required capability are ordered by ascending priority, then identity. The first executor wins. A failure lists the enabled executors and their capabilities.

### 6. Materialization and artifact validation

Only the selected executor's `materialize` function is forced. Its artifact must provide:

- a path-like `retainedArtifactTarget`;
- a known `cleanupStrategy`;
- a known `selfHealStrategy`.

The final manifest entry records the selected executor identity and protocol version. The default conflict policy is inserted here, so runtime consumers never infer an absent value.

### 7. Manifest emission

Entries are sorted by canonical filesystem identity before materialization. `contract.emit` produces both native Nix data and JSON from the same list.

## Principal model

A principal contains an authority and a concrete context:

```nix
{
  authority = {
    scope = "user";
    identity = "feltfomo";
  };
  managedRoot = "/home/feltfomo";
  ctx = {
    host = ...;
    user = ...;
  };
}
```

System authority identities must use canonical `<system>/<name>` form. Home-relative file declarations are generated only for user principals.

## Extension rules

When adding a representation:

1. Add a capability to the contract.
1. Add a stable executor identity and protocol version.
1. Register an executor with `lifecycle-baseline` plus the new capability.
1. Return explicit cleanup and self-heal strategies.
1. Add forcing tests proving unrelated executors stay lazy.
1. Add manifest and runtime compatibility tests.

Do not branch the compiler on a representation name when capability selection can express the requirement.

When changing the manifest, bump `schemaVersion` and coordinate the consumer migration. Ledger schema changes are versioned independently.
