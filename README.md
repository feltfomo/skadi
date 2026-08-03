# skadi

A personal NixOS fleet built with [Den](https://github.com/denful/den), Home Manager, and a small set of local configuration subsystems. One flake defines physical hosts, installer targets, users, reusable aspects, managed files, and the checks that keep them aligned.

## Systems

- **khion** — NVIDIA desktop with Wayland, gaming, impermanence, and the full `feltfomo` environment.
- **lumi** — laptop with GNOME, `feltfomo`, and the restricted `grandpa` account.
- **vm** — throwaway QEMU target for testing the installer, disk layout, secrets, and rollback flow.
- **generic** — hardware-discovered installation target with a minimal `owner` account.

`khion` and `lumi` are the real machines. `vm` and `generic` exercise the same configuration and installation machinery without pretending to be additional fleet hardware.

## How the configuration fits together

Den defines the host and user roster and activates feature **aspects** from `modules/aspects/`. Host aspects own NixOS features; user aspects own Home Manager features. Machine-specific hardware, disk, boot, and networking facts stay under `modules/hosts/`.

The local libraries under `modules/_lib/` provide the machinery around those aspects:

- **Program** turns a compact package, file, directory, and template declaration into matching NixOS, Home Manager, and Furnish slices.
- **Ownerships** validates host and user claims, selects units for one context, and merges the surviving plain Nix values.
- **Furnish** describes managed files and directories; its Rust coordinator reconciles manifests onto the filesystem with ledger, recovery, and safety checks.
- **Krisis** provides structured diagnostic aggregation and safe rendering for the other libraries.

The normal flow is:

```text
aspect declarations
  → Program or explicit Ownerships units
  → host/user selection and merge
  → NixOS + Home Manager configuration
  → Furnish manifests and coordinator reconciliation
```

These are repository libraries, not requirements for unrelated Nix configurations. Ownerships and its unit import helpers can also be used without Den.

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs, caches, Den wiring, and shared module arguments. |
| `modules/aspects/` | Reusable system and user features. |
| `modules/hosts/` | Host declarations plus hardware, disk, boot, and networking facts. |
| `modules/users/` | User declarations, account policy, Home Manager features, and persistence. |
| `modules/_lib/program.nix` | High-level package and managed-file declaration surface. |
| `modules/_lib/ownerships/` | Claim, selection, merge, trace, matrix, and standalone unit discovery. |
| `modules/_lib/furnish/` | Managed-file declaration engine and Rust reconciliation coordinator. |
| `modules/_lib/krisis/` | Structured diagnostics and safe rendering. |
| `configs/` | Source configuration trees consumed by aspects and Program. |
| `docs/` | User and maintainer documentation for the local subsystems. |
| `scripts/` | Installer, VM, coordinator, and regression entry points. |
| `tests/` | Checked-in regression manifests and baselines. |
| `go/` | VM golden-image rebuild tooling and harness code. |
| `.github/workflows/ci.yml` | Repository CI. |

## Documentation

- [Program usage and behavior](docs/program.md)
- [Ownerships](docs/ownerships/README.md)
- [Ownerships standalone usage](docs/ownerships/USAGE.md)
- [Furnish](docs/furnish/README.md)
- [Furnish coordinator](docs/furnish/coordinator/README.md)
- [Krisis](docs/krisis/README.md)

## Build and deploy

Format and run the complete repository gate:

```fish
nix fmt
nix flake check -L
```

Test a host configuration without changing the boot default:

```fish
sudo nixos-rebuild test --flake /etc/skadi#khion
```

Make the tested generation the boot default:

```fish
sudo nixos-rebuild switch --flake /etc/skadi#khion
```

Inspect a system closure before activation:

```fish
nix build .#nixosConfigurations.khion.config.system.build.toplevel
nix store diff-closures /run/current-system ./result
```

Replace `khion` with the intended real host. The VM and generic targets are driven through the installer and test tooling rather than deployed over a running physical machine.

## Operational notes

- `khion` uses impermanence and restores a blank root snapshot at boot. Anything that must survive belongs in the declared system or user persistence sets.
- Never run Disko or the installer against a running host disk. Both are allowed to repartition storage.
- Provision required SOPS secrets before rebuilding a new account or machine. Use `nixos-rebuild test` and confirm login from a fresh TTY before `switch`.
- Secrets live outside the Notion synchronization surface. Do not add encrypted or decrypted secret material to synchronized mappings.
- `nix fmt` runs the repository's configured formatting and static-analysis pipeline; a second pass should converge with no changes.
- The `unknown flake output 'denful'` warning is expected from the current Den integration.
