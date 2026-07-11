# skadi

NixOS config for two machines, built on Den. one flake, one set of feature
modules, composed per host.

## hosts

- khion: nvidia desktop. hyprland and gnome, steam, impermanence (root wiped to
  a blank snapshot on every boot).
- lumi: gnome laptop.

## how it fits together

Den loads everything under modules/ automatically. features are aspects: small
modules under modules/aspects/ that each set up one thing (shell, theming,
hyprland, firefox, ...). a host turns aspects on by listing them in the includes
of its host aspect, and Den activates the host aspect named after the host.

aspects carry nixos config, home-manager config, or both. Den 0.17 does not
forward home-manager config from a host to its users, so home aspects are listed
on the user in modules/users/feltfomo.nix, not on the host. nixos-only aspects
stay on the host.

aspects also say who they are for, right on the config. a hosts or users list on
a block, file, or option path claims it for those hosts or users; untagged
config is for everyone. the ownerships engine in modules/_lib/ownerships/ reads
those claims and merges what survives: resolve builds the per-user view,
resolveSystem the per-host one. see docs/ownerships/README.md.

the username lives in exactly one file: modules/users/feltfomo.nix.

## layout

flake.nix                     inputs and Den wiring
modules/den.nix               Den schema, host and user classes, stateVersion
modules/aspects/              feature modules (base, system, shell, theming,
                              hyprland, kitty, fuzzel, walker, thunar,
                              spicetify, noctalia, firefox, steam, gnome,
                              wayland, qt-hm, impermanence, gpu-nvidia,
                              docker, hermes, notion-sync, sops)
modules/hosts/                khion.nix, lumi.nix, and per-host hardware in
                              _khion/ and _lumi/ (disko, hardware,
                              networking, environment)
modules/users/feltfomo.nix    the user, and the home aspects it includes
modules/_lib/program.nix      turns a small spec into matching home-manager,
                              hjem, and host-only nixos config
modules/_lib/ownerships/      ownership engine: aspects claim config for
                              hosts or users; see docs/ownerships/ for the how-to
modules/_pkgs/lucid.nix       spicetify Lucid theme, built from source
modules/graalvm-oracle-21/    graalvm overlay
modules/formatting.nix        treefmt config
modules/checks.nix            per-host build and treefmt checks
.github/workflows/ci.yml      CI

## build and deploy

    nix fmt                                              format the tree
    nix flake check                                      build both hosts, run treefmt
    sudo nixos-rebuild test --flake /etc/skadi#khion     activate now, reverts on reboot
    sudo nixos-rebuild switch --flake /etc/skadi#khion   make it the boot default

see what an upgrade changes before switching:

    nix build .#nixosConfigurations.khion.config.system.build.toplevel
    nix store diff-closures /run/current-system ./result

## notes

- impermanence: khion wipes root on every boot. anything not under
  environment.persistence is gone after reboot. declare new system paths in
  modules/aspects/impermanence.nix and new user paths in
  modules/users/feltfomo.nix before relying on them.
- never run disko or disko-install against a running host. it repartitions.
- nixfmt runs after deadnix and statix in formatting.nix so one nix fmt pass
  converges.
- spicetify Lucid needs modules/_pkgs/package-lock.json. if it drifts,
  regenerate it (npm install --package-lock-only in the upstream repo), run
  prefetch-npm-deps on the lock, and update npmDepsHash in lucid.nix.
- the "unknown flake output denful" warning is expected.
- electron-39.8.10 is allowed for logseq. drop it when logseq updates.
- gifski is built with doCheck = false because its upstream test is flaky.
- secrets are managed with sops-nix. the encrypted store is secrets/secrets.yaml,
  decrypted with khion's ssh host key (persisted across the boot rollback). the
  sops aspect lives in modules/aspects/sops.nix and .sops.yaml holds the recipient
  age key. keep secrets/ in the notion-sync ignore list so the encrypted file
  never round-trips through Notion. to provision: derive the age key from the host
  key, paste it into .sops.yaml, then `sops secrets/secrets.yaml`. rebuild with
  `nixos-rebuild test` first and confirm login on a fresh tty before `switch`.
