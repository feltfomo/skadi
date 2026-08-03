# Furnish runtime integration

`modules/_lib/furnish/runtime.nix` turns the pure compiler output into a closure-retained manifest and arranges reconciliation during activation and boot.

This document describes the NixOS boundary. The coordinator's internal Rust algorithms are documented separately.

## NixOS options

```nix
lexicon.furnish = {
  enable = true;

  state = {
    path = "/var/lib/furnish";
    durability = "ephemeral";
    requiresMountsFor = [ ];
  };

  declarations = [ ... ];

  # read-only outputs
  manifestData = [ ... ];
  manifestPath = /nix/store/...;
  ledgerPath = "/var/lib/furnish/applied-state.json";
};
```

### `enable`

Enables runtime reconciliation. Disabled means inert, not an enabled reconciliation against an empty desired state.

### `state.path`

Directory containing the applied-state ledger and migration backup.

### `state.durability`

`durable` or `ephemeral`. This is an asserted property of the host's storage layout; Furnish does not arrange persistence itself.

### `state.requiresMountsFor`

Extra filesystems the service must wait for, normally including the filesystem that carries durable state.

### `declarations`

Host-selected declarations supplied by Program or another integration layer.

### Read-only projections

`manifestData`, `manifestPath`, and `ledgerPath` expose the compiled state for runtime wiring and regression inspection.

## Native executors

The runtime registers two priority-zero executors:

- `furnish/native-symlink`, with `symlink` and `lifecycle-baseline` capabilities;
- `furnish/native-writable`, with `writable` and `lifecycle-baseline` capabilities.

Both retain the selected source through `builtins.path`. Their cleanup and self-heal strategy matches their representation.

Generated derivation sources are also added to `system.extraDependencies`, keeping build-time inputs needed to reconstruct retained artifacts in the system closure.

## Manifest retention

When enabled, `pkgs.writeText` writes the versioned desired-state JSON. String context in retained artifact targets makes those targets closure dependencies of the manifest and active system.

An enabled host always receives a manifest, including an empty entry list. Empty desired state is meaningful because it allows the coordinator to retire entries that disappeared from configuration.

## Activation behavior

During ordinary `switch-to-configuration`, the activation script runs reconciliation immediately.

Inside the NixOS stage-1 activation path, it defers reconciliation to `furnish.service`. Destination and state filesystems may not be mounted yet.

## Systemd service

`furnish.service` is a oneshot wanted by `multi-user.target`.

It:

- runs after `local-fs.target`;
- requires mounts for every compiled destination plus `state.requiresMountsFor`;
- remains active after a successful boot reconcile;
- invokes the same coordinator command as activation;
- receives a host-specific lock name derived from system and hostname.

`RemainAfterExit` prevents a later switch during the same boot from replaying the boot-only service path; the activation script handles switches.

## Ledger contract

The applied-state ledger is distinct from the desired-state manifest:

- the manifest records what configuration requests;
- the ledger records what this machine actually applied and the evidence required for safe transitions.

They have independent schema versions. The current ledger is version 2 at `applied-state.json`. Before the first v2 write, the runtime contract reserves `applied-state.v1.json` as a rollback copy of the state consumed by migration.

The coordinator refuses actions it cannot prove safe from manifest and ledger evidence. Nix wiring must therefore ensure the ledger filesystem is available before reconciliation.

## Runtime diagnostic contract

The manifest carries the versioned set of coordinator diagnostic codes, covering invalid manifests, unsupported executors, destination validation, traversal, conflicts, staging and final verification, ledger failures, repair, transition refusal, retirement, and pending recovery.

The Nix layer treats this registry as data. Runtime documentation for the meaning and recovery procedure of each code belongs with the coordinator pass.

## Operational inspection

Useful Nix projections include:

```nix
config.lexicon.furnish.manifestData
config.lexicon.furnish.manifestPath
config.lexicon.furnish.ledgerPath
```

The coordinator binary is installed in `environment.systemPackages` when Furnish is enabled.

Do not manually edit the generated manifest. It is a system-closure artifact and will be replaced on the next evaluation.

## Changing runtime wiring

Preserve these invariants:

- the active system retains the manifest and artifact closure;
- an enabled empty manifest remains observable;
- boot reconciliation waits for destination and ledger filesystems;
- activation and service use the same coordinator package and command contract;
- disabled mode performs no reconciliation;
- the ledger and manifest remain independently versioned.
