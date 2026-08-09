# skadi

A personal NixOS fleet built with [Den](https://github.com/denful/den), Home Manager, and a set of configuration frameworks this flake takes as inputs. One flake defines physical hosts, installer targets, users, reusable aspects, managed files, and the checks that keep them aligned.

## Systems

- **khion** — NVIDIA desktop with Wayland, gaming, impermanence, and the full `feltfomo` environment.
- **lumi** — laptop with GNOME, `feltfomo`, and the restricted `grandpa` account.
- **vm** — throwaway QEMU target for testing the installer, disk layout, secrets, and rollback flow.
- **generic** — hardware-discovered installation target with a minimal `owner` account.

`khion` and `lumi` are the real machines. `vm` and `generic` exercise the same configuration and installation machinery without pretending to be additional fleet hardware.

## How the configuration fits together

Den defines the host and user roster and activates feature **aspects** from `modules/aspects/`. Host aspects own NixOS features; user aspects own Home Manager features. Machine-specific hardware, disk, boot, and networking facts stay under `modules/hosts/`.

The machinery around those aspects lives in separate repositories, consumed as flake inputs:

- **[lexicon](https://github.com/feltfomo/lexicon)** carries Program, Ownerships, Furnish, and the Den integration. Program turns a compact package, file, directory, and template declaration into matching NixOS, Home Manager, and Furnish slices. Ownerships validates host and user claims, selects units for one context, and merges the surviving plain Nix values. Furnish describes managed files and directories.
- **[furnish-coordinator](https://github.com/feltfomo/furnish-coordinator)** is the Rust reconciler that applies Furnish manifests onto the filesystem with ledger, recovery, and safety checks. Lexicon owns this input, so this flake never names it.
- **[krisis](https://github.com/feltfomo/krisis)** provides structured diagnostic aggregation and safe rendering.
- **[axiom](https://github.com/feltfomo/axiom-nix)** provides the schemas, registries, and phase laws the others validate against.

The normal flow is:

```text
aspect declarations
  → Program or explicit Ownerships units
  → host/user selection and merge
  → NixOS + Home Manager configuration
  → Furnish manifests and coordinator reconciliation
```

Those frameworks are usable outside this repository and are not requirements for unrelated Nix configurations. Ownerships and its unit import helpers can also be used without Den.

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs, caches, Den wiring, and shared module arguments. |
| `modules/den.nix` | Den schema defaults and fleet module entry point. |
| `modules/aspects/` | Reusable system and user features. |
| `modules/hosts/` | Host declarations plus hardware, disk, boot, and networking facts. |
| `modules/users/` | User declarations, account policy, Home Manager features, and persistence. |
| `modules/checks/` | Parity check for this fleet's own hosts and users. |
| `modules/flake/` | Per-system checks, development shells, and formatting wiring. |
| `modules/installer/` | Installer ISO and installation-target composition. |
| `modules/tools/` | Runnable flake applications and their Nix wrappers. |
| `configs/` | Source configuration trees consumed by aspects and Program. |
| `pkgs/` | Local package definitions and checked-in binary source inputs. |
| `scripts/` | Production installer and runtime command bodies. |
| `tests/` | Repository shell gates, regression manifests, and checked-in baselines. |
| `tools/` | Go repository tooling, including the VM golden-image rebuild implementation. |
| `.github/workflows/ci.yml` | Repository CI. |

## Documentation

Each framework documents itself in its own repository: [lexicon](https://github.com/feltfomo/lexicon/tree/main/docs), [furnish-coordinator](https://github.com/feltfomo/furnish-coordinator/tree/main/docs), [krisis](https://github.com/feltfomo/krisis/tree/main/docs), and [axiom](https://github.com/feltfomo/axiom-nix/tree/main/docs).

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
- Updating a framework is `nix flake update lexicon` (or `axiom`, `krisis`) followed by the usual gate.
- The `unknown flake output 'denful'` warning is expected from the current Den integration.
