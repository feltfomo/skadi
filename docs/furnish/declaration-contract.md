# Furnish declaration contract

Furnish declarations are internal records produced by integration layers such as `program` and `files.mkDeclarations`. They are not the preferred aspect-authoring syntax.

## Declaration shape

```nix
{
  label = "files[.config/example/config.toml]";
  filesystemNamespace = "x86_64-linux/khion";
  authority = {
    scope = "user";
    identity = "feltfomo";
  };
  managedRoot = "/home/feltfomo";
  destination = ".config/example/config.toml";
  representation = "symlink";
  source = {
    kind = "path";
    value = ./config.toml;
  };
  onConflict = "error";
  provenance.source = "modules/aspects/example.nix";
}
```

Ownership claim keys may exist before selection. They are removed before the declaration reaches the manifest.

## Fields

| Field | Contract |
| --- | --- |
| `label` | Required string used in diagnostics and provenance. |
| `filesystemNamespace` | Required string separating identities belonging to different host filesystems. |
| `authority.scope` | `user` or `system`. |
| `authority.identity` | Canonical string identity; system identities must contain `/`. |
| `managedRoot` | Absolute root the destination must remain beneath. |
| `destination` | Absolute or root-relative destination. |
| `representation` | Non-empty capability name, currently `symlink` or `writable`. |
| `source.kind` | Required source-kind string. |
| `source.value` | Required lazy payload consumed by the selected executor. |
| `onConflict` | Optional `error`, `source-wins`, or `runtime-wins`. |
| `provenance` | Optional attrset whose values are strings. |

## Filesystem identity

After normalization, identity is:

```text
<filesystem namespace>:<absolute destination>
```

For example:

```text
x86_64-linux/khion:/home/feltfomo/.config/example/config.toml
```

The namespace is not the authority. Several authorities can claim paths in the same host filesystem, which is why Furnish performs host-wide collision indexing.

## Managed-root rules

The normalized destination must:

- be absolute after joining with `managedRoot`;
- not escape through `..`;
- not equal `/`;
- not equal the managed root itself;
- remain a strict descendant of the managed root.

Normalization is lexical. It does not follow symlinks or inspect the live filesystem during evaluation.

## Representations

### `symlink`

Requires the native symlink executor. Its lifecycle strategy is `exact-symlink-target`.

### `writable`

Requires the native writable executor. Its lifecycle strategy is `exact-source-content`.

Representation describes the required executor capability. The compiler does not hard-code executor identity into the declaration.

## Conflict policies

| Policy | Intent |
| --- | --- |
| `error` | Divergence from the recorded baseline is an error. |
| `source-wins` | Desired source content wins when divergence can be resolved. |
| `runtime-wins` | Runtime content is retained when divergence can be resolved. |

The exact reconciliation behavior belongs to the coordinator contract. The Nix layer guarantees every emitted entry contains one explicit policy.

## Executor contract

```nix
{
  identity = "furnish/native-symlink";
  priority = 0;
  enabled = true;
  protocolVersion = 1;
  capabilities = [
    "lifecycle-baseline"
    "symlink"
  ];
  materialize = declaration: {
    retainedArtifactTarget = ...;
    cleanupStrategy = "exact-symlink-target";
    selfHealStrategy = "exact-symlink-target";
  };
}
```

Executor identity and protocol version are persisted in the manifest. Changing their meaning is a compatibility change.

## Manifest document

The current manifest document has this shape:

```nix
{
  schemaVersion = 2;
  diagnosticContract = {
    schemaVersion = 1;
    codes = { ... };
  };
  entries = [ ... ];
}
```

Each entry contains:

- schema version;
- filesystem identity;
- authority;
- managed root;
- representation;
- retained artifact target;
- executor identity and protocol version;
- cleanup and self-heal strategies;
- conflict policy;
- declaration provenance.

The diagnostic code registry is part of the runtime contract. Renaming a code is not only a wording change.

## Laziness requirements

Validation may inspect the shape of `source`, but it must not force `source.value`. Likewise, executor validation must not force `materialize`. These values may contain derivations, generated content, secrets, or deliberately inactive payloads.

Only ownership-selected declarations reach destination derivation and executor materialization.
