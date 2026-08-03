# Furnish

Furnish compiles selected filesystem declarations into a deterministic desired-state manifest and wires that manifest into NixOS reconciliation.

It is infrastructure behind `program.files`, `program.directories`, and Noctalia seed files. Normal aspect authors should use `program`; they should not construct Furnish declarations directly unless they are extending the filesystem machinery itself.

This documentation covers the Nix boundary only. The Rust coordinator's reconciliation algorithms, crash recovery, ledger implementation, and filesystem internals belong to a separate documentation pass.

## Responsibilities

The Nix layer owns:

- the versioned manifest and diagnostic contract;
- declaration validation;
- Ownerships-backed selection;
- destination normalization;
- host-wide collision detection;
- executor validation and capability selection;
- retained artifact materialization;
- manifest emission;
- NixOS activation and service wiring.

It deliberately does not perform filesystem mutation during evaluation.

## Data flow

```text
Program file entries
→ principal-aware Furnish declarations
→ shape validation
→ ownership selection
→ destination normalization
→ collision index
→ executor selection
→ artifact validation
→ manifest JSON
→ furnish-coordinator reconcile
```

See:

- [Architecture](architecture.md)
- [Declaration contract](declaration-contract.md)
- [Runtime integration](runtime-integration.md)

## Public and internal surfaces

`modules/_lib/furnish/default.nix` exports:

| Export | Role |
| --- | --- |
| `compile` | Compile declarations and executors into manifest projections. |
| `contract` | Versioned constants and manifest constructors. |
| `core` | Validation, selection, indexing, diagnostics, and test seams. |
| `files.mkDeclarations` | Lower selected home-relative file entries to declarations. |
| `runtime` | NixOS module import. |

Only `files.mkDeclarations` and the runtime module are used by Program. Most `core` exports exist for internal composition and tests.

## Invariants

- No declaration is silently selected when Ownerships is disabled.
- Inactive ownership payloads are not forced.
- Every managed destination stays lexically beneath its managed root.
- Filesystem identity is canonical before collision detection.
- Collisions fail with all claimants; source order never chooses a winner.
- Executor ordering is deterministic by priority and identity.
- Unselected executor implementations remain lazy.
- Every manifest entry names its conflict policy and lifecycle strategies explicitly.
- An enabled runtime emits an empty manifest when there are no declarations so retirement can still occur.

## Verification

```fish
nix fmt
nix flake check -L
```
