# skadi

my nixos config for khion, my nvidia desktop, and lumi, my laptop. both track nixos-unstable and use lix.

hyprland, niri and mango are configured for both machines. lumi uses silentsddm for login and has a separate `grandpa` account with plasma and no admin access. each feature keeps its config files and color templates next to its module under [modules/](modules/).

both machines use luks-encrypted btrfs. the root resets to a blank snapshot at boot, while `/home`, `/nix` and `/persist` survive. system services declare the state they need to keep in their aspects.

## daily use

```fish
praxis rebuild khion
```

use `lumi` on the laptop. this formats the repo, then asks before running the selected host's den wrapper to build and switch through `nh os`. it doesn't deploy over ssh. generation and full flake checks are separate commands.

praxis uses `/etc/skadi` even when run from another directory.

| command                       | what it does                                               |
| ----------------------------- | ---------------------------------------------------------- |
| `praxis check`                | build both machines and run the repo checks                |
| `praxis fmt`                  | format the repo                                            |
| `praxis gen`                  | regenerate flake.nix from the module declarations           |
| `praxis update input lexicon` | update one flake input                                     |
| `praxis flake update`         | update all flake inputs and the Wooting background service |
| `praxis update wooting`       | update just the Wooting background service                 |

`nfu` is the fish abbreviation for `praxis flake update`. plain `nix flake update` skips Wooting, which has its own [version and hash](modules/hardware/wooting/_package/release.json).

to preview a rebuild or pass a dry switch through to `nh`:

```fish
praxis --plain plan rebuild khion
praxis rebuild khion -- --dry
```

the dry switch formats the repo, then lets `nh` build and preview the selected host without activating it. `praxis list` and `praxis help rebuild` show the other options.

if praxis isn't installed yet, enter the dev shell or run it through nix:

```fish
nix develop /etc/skadi
```

```fish
nix run /etc/skadi#praxis -- rebuild khion
```

## remote herdr sessions

herdr combines khion and lumi itself. both machines are declared once in [`_machines.nix`](modules/terminals/herdr/_machines.nix), which the herdr config lists under `[fleet]`. run these from a terminal on the machine you are using:

```fish
herdr
herdr --session skadi
herdr --fleet lumi --session skadi
herdr --fleet lumi --session research --new
praxis herdr machines
```

plain `herdr` opens a combined window for the session, with this device selected. herdr finds this device by its host name and connects to it locally, without SSH. `--fleet lumi` selects lumi's copy of the session instead; it must already be running there, because connecting never starts a stopped peer session. `--new` creates the named session on that machine first. names use 1-64 ASCII letters, numbers, dots, underscores or hyphens. `.`, `..` and `default` are reserved. `praxis herdr machines` lists the declared machines without probing them.

the window shows only the selected session. each machine contributes its own spaces from that session; other sessions are never attached or shown. the sidebar is a tree of machines and their spaces. "This device" uses local IPC, while the other machine uses SSH over Tailscale. an offline machine does not block the local terminal. the agents panel defaults to this space; this machine and all machines also stay within the session. the session picker (`prefix+g`) lists sessions across both machines and opens or creates one in a fresh window.

opening a peer connection also opens the same-named local session for local editing.

connection windows keep their sidebar preferences under `$XDG_STATE_HOME/herdr/connections`, or `~/.local/state/herdr/connections` by default. windows opened by the old praxis helper used different directories there, so their sidebar preferences don't carry over. herdr launched with `HERDR_SOCKET_PATH` or `HERDR_CLIENT_SOCKET_PATH` set keeps its ordinary window and saved machines.

SSH uses your existing keys and Tailscale hostnames. the other machine must be awake and reachable. both machines need the patched Herdr binary for combined connections. an older peer fails with an update notice.

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

## lumi's plasma account

`grandpa` gets chrome and stock ghostty through nix and installs other apps from discover's per-user flathub source. chrome stays installed across rebuilds and isn't managed by discover. the launcher lists chrome, files, discover, settings, and apps or website shortcuts added under that account.

plasma starts in Breeze Dark with Papirus Dark icons, 12-point text and a 48-pixel Windows-style cursor. the cursor size stays adjustable in settings. initial files are copied only when absent. the palette and cursor are applied once, so later changes through settings remain writable and survive rebuilds. browser data and user flatpaks persist with `/home`.

gnome, gdm and plain sddm remain available as aspects. lumi selects plasma and silentsddm; adding a desktop's module to the repository doesn't enable it.

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
