# skadi

my nixos config for khion, my nvidia desktop, and lumi, my laptop. both track nixos-unstable and use lix.

hyprland, niri and mango are configured for both machines. lumi also has gnome and a separate `grandpa` account without admin access. each feature keeps its config files and color templates next to its module under [modules/](modules/).

both machines use luks-encrypted btrfs. the root resets to a blank snapshot at boot, while `/home`, `/nix` and `/persist` survive. system services declare the state they need to keep in their aspects.

## daily use

```fish
praxis rebuild khion
```

use `lumi` on the laptop. this regenerates `flake.nix`, formats the repo and runs the checks, including builds of both machines. it asks before switching the local system. it doesn't deploy over ssh.

praxis uses `/etc/skadi` even when run from another directory.

| command                       | what it does                                               |
| ----------------------------- | ---------------------------------------------------------- |
| `praxis check`                | build both machines and run the repo checks                |
| `praxis fmt`                  | format the repo                                            |
| `praxis update input lexicon` | update one flake input                                     |
| `praxis flake update`         | update all flake inputs and the Wooting background service |
| `praxis update wooting`       | update just the Wooting background service                 |

`nfu` is the fish abbreviation for `praxis flake update`. plain `nix flake update` skips Wooting, which has its own [version and hash](modules/hardware/wooting/_package/release.json).

to preview a rebuild or pass a dry switch through to `nh`:

```fish
praxis --plain plan rebuild khion
praxis rebuild khion -- --dry
```

the dry switch still runs generation, formatting and checks. `praxis list` and `praxis help rebuild` show the other options.

if praxis isn't installed yet, enter the dev shell or run it through nix:

```fish
nix develop /etc/skadi
```

```fish
nix run /etc/skadi#praxis -- rebuild khion
```

## editing the config

| path                                                       | what's there                                                       |
| ---------------------------------------------------------- | ------------------------------------------------------------------ |
| [modules/hosts/](modules/hosts/)                           | each machine's aspects, hardware, disks and bootloader             |
| [modules/users/](modules/users/)                           | accounts and home manager settings                                 |
| `modules/<area>/`                                          | features, each a single module or a folder with its files          |
| [modules/desktop/bindings/](modules/desktop/bindings/)     | [shared desktop bindings](modules/desktop/bindings/bindings.md)    |
| [modules/installer/](modules/installer/)                   | the installer iso, skadi-install and the vm test harness           |
| [modules/flake/](modules/flake/)                           | inputs, checks, formatting, the dev shell and `skadi.packages`     |
| [praxis.nix](praxis.nix)                                   | maintenance commands                                               |

the areas are `ai`, `browsers`, `desktop`, `dev`, `editors`, `gaming`, `hardware`, `media`, `shell`, `social`, `system` and `terminals`. a feature folder keeps the files it deploys in `config/`, because furnish copies whole directories into the home and would otherwise ship the module too.

every `.nix` file under `modules/` is imported as a module, except paths containing `/_`. put package recipes, host hardware and other plain nix files there. to share a package or value between features, publish it through `skadi.packages` or another `skadi.*` option instead of importing across feature folders.

`flake.nix` is generated. change input declarations in the relevant module, then run `praxis gen`. [outputs.nix](outputs.nix) sets up module imports and the shared helpers from [lexicon](https://github.com/feltfomo/lexicon).

after changing `praxis.nix`, use a fresh dev shell or `nix run /etc/skadi#praxis` to try it. the installed command keeps its old declarations until the next activation.

when adding a system service, declare any state it needs across reboots in `persistence.directories` or `persistence.files`. `/home` already persists, so it doesn't need those declarations.

## installation

build the installer from the repo:

```fish
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

flash `result/iso/*.iso` in raw mode, then boot it. use `nmtui` if you need wifi. on the iso, `skadi-install` opens a host and aspect picker, or you can choose a host directly:

```fish
skadi-install khion
```

this erases the target disk. the installer clones skadi from github when it runs, prompts for passwords and service secrets, and installs the system with a checkout at `/etc/skadi`. building a local iso doesn't pin the config it will install. the installer is in [modules/installer/skadi-install.sh](modules/installer/skadi-install.sh).

`--drop gpu-nvidia,steam` omits selected top-level aspects for that installation. it doesn't edit the host's aspect list. don't run the installer or disko on a running skadi system.

there are two extra targets in [modules/hosts/](modules/hosts/):

| target    | purpose                                                                    |
| --------- | -------------------------------------------------------------------------- |
| `vm`      | test installation and first boot in qemu                                   |
| `generic` | detect hardware and install to a single disk with an `owner` admin account |

`generic` requires exactly one disk and must be selected explicitly with `skadi-install generic`.

to test the installer in a disposable vm:

```fish
nix run .#vm-test -- --host vm
```

this needs kvm and the dedicated private key at `~/.cache/skadi-vm/vm-test-key`, matching the public key in [the iso config](modules/installer/iso.nix). it installs to an encrypted virtual disk, boots it without the iso, and checks system health, home manager and furnish. logs stay in `~/.cache/skadi-vm`; pass `--keep` to retain the disk too.

## recovery

the host wrappers work without praxis. with no action they build; `switch` activates through `nh os`:

```fish
nix run .#khion
nix run .#khion -- switch --dry
nix run .#khion -- switch
```

replace `khion` with `lumi` on the laptop. to compare a build with the running system:

```fish
nix build .#nixosConfigurations.khion.config.system.build.toplevel
nix store diff-closures /run/current-system ./result
```

`sudo nixos-rebuild switch --flake /etc/skadi#khion` is the fallback if the wrapper isn't usable. before switching a new account or machine, provision its sops secrets and verify login on a fresh tty with a test activation.

## remote tools

pi's servers are declared in [modules/ai/pi/config/mcp-adapter.json](modules/ai/pi/config/mcp-adapter.json). context7 and github connect directly to their hosted servers. set pi's github token through the masked prompt:

```fish
pi-mcp-adapter token set github
```
