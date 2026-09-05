# skadi

My NixOS fleet. One flake owns the machines, users, desktop features, installer, and the checks that keep them bootable.

Den composes the fleet, Home Manager handles user configuration, and Lexicon handles program declarations and managed files. They are plumbing, not the point of the repository.

## Systems

- **khion** is the NVIDIA desktop, with Wayland, gaming, impermanence, and the full `feltfomo` environment.
- **lumi** is the GNOME laptop, with `feltfomo` and a restricted family account.
- **vm** is a disposable QEMU target for the complete installer and first-boot path.
- **generic** discovers its disk and hardware during installation and starts with a minimal `owner` account.

`khion` and `lumi` are real machines. `vm` and `generic` exist to prove the install path without gambling on either one.

## Layout

| Path | What lives there |
| --- | --- |
| `flake.nix` | Inputs, caches, Den wiring, and shared module arguments |
| `modules/aspects/` | Reusable system and user features |
| `modules/hosts/` | Host declarations, hardware, disks, bootloaders, and networking |
| `modules/users/` | Accounts, Home Manager features, and user persistence |
| `modules/installer/` | Installer ISO and temporary install-target composition |
| `modules/flake/` | Checks, development shells, and formatting |
| `modules/tools/` | Runnable flake applications such as the VM test |
| `configs/` | Configuration trees installed by feature aspects |
| `scripts/` and `tests/` | Installer/runtime scripts and skadi-specific regression coverage |

## Build and check

```fish
nix fmt
nix flake check -L
```

The full check builds both real hosts and runs the repository checks. Den currently emits an `unknown flake output 'denful'` warning; it is expected.

Build khion without activating it:

```fish
nix build .#nixosConfigurations.khion.config.system.build.toplevel
nix store diff-closures /run/current-system ./result
```

Test a generation before making it the boot default:

```fish
sudo nixos-rebuild test --flake /etc/skadi#khion
sudo nixos-rebuild switch --flake /etc/skadi#khion
```

Use the intended real host name in place of `khion`.

## Installer

`skadi-install <host>` runs the destructive install path from the installer ISO. With no host on a TTY it opens the host and aspect picker. `--drop` removes selected top-level aspects from that install without editing the committed host.

The end-to-end VM gate builds the ISO, installs onto a disposable encrypted disk, removes the ISO, and waits for the installed system to settle:

```fish
nix run .#vm-test -- --host vm
```

Never run Disko or `skadi-install` against a running host. Both are allowed to repartition disks.

## Operational constraints

- Khion restores a blank root snapshot at every boot. Persistent state must be declared under system or user persistence before anything relies on it.
- SOPS secrets must exist before rebuilding a new account or machine. Test login from a fresh TTY before switching the boot generation.
- Desktop Commander hosts the remote MCP tools on khion behind one authenticated gateway. Git, secrets, and privileged activation stay outside that service.
- Lexicon owns Axiom, Krisis, and Furnish Coordinator. Skadi consumes only the Lexicon input and updates it with `nix flake update lexicon`.
- Installer artifacts belong under `~/.cache/skadi-vm`, not in this repository.
