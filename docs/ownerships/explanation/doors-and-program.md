# The two doors, and `program`

A unit list has to resolve against *something*: the machine and person being built. That's the build context, and there are two scopes it can arrive in.

## Two scopes, two doors

- **User scope** — the context carries both a `host` and a `user`. This is where per-user config lives: home-manager and hjem content. A unit here may narrow on `users` / `exceptUsers`.
- **Host-only scope** — the context carries a `host` and *no* user. This is for nixos slices where there's no single user to narrow to: a compositor, a system package, a systemd service. Narrowing on `users` here is a hard [author-time error](../reference/errors.md#author-time-surface) — a host-wide slice binds no user.

The surface exposes one door per scope, each bound once to the fleet roster: `mkResolve` (user scope) and `mkResolveSystem` (host-only). See [doors and `program` args](../reference/doors-and-program-args.md) for their signatures.

You will almost never call those doors directly. **Nothing shipped in skadi does.** They're the mechanism; the front door is `program`.

## `program` is the front door

`program` (`modules/_lib/program.nix`) is a small spec DSL for the shape most aspects want — install a package, link some files, write some templates, and optionally own a nixos slice. It forwards the claim keys straight through to the two doors underneath, so you author claims exactly the same way whether a field is per-user or host-only.

An aspect gets `program` handed in as a module arg, already bound to the roster. It hands `program` a spec:

```nix
den.aspects.kitty = program {
  pkg = pkgs: pkgs.kitty;                              # a package for home.packages
  files = [ { dest = "..."; src = "..."; } ];           # static file links (hjem)
  templates = [ { name = "..."; templateFile = "..."; } ]; # noctalia templates
};
```

The spec fields (`pkg`, `imports`, `files`, `templates`, `noctaliaConfig`, `nixos`) and their exact shapes are in [the reference](../reference/doors-and-program-args.md#program-spec). What matters here is *how ownership flows through them*.

## Where the claims land

`program` splits a spec into two independent resolves:

- **Home slices** (`pkg`, `imports`, `files`, `templates`, `noctaliaConfig`) resolve at **user scope**. Claim keys on the whole spec narrow every home field at once; claim keys on an individual `files` / `templates` entry narrow just that entry. That per-entry narrowing is how one linked file can go to a single user while the rest of the aspect is global.
- **The nixos slice** (`spec.nixos`) resolves **host-only**. `spec.nixos` is a function `{ pkgs, config, ... }: [ units ]` — it returns its own unit list, and *those* units carry their own claims. The spec-level claim does **not** reach into `spec.nixos`; a host-only nixos unit repeats its host claim itself.

That last point trips people up, so it's worth stating flatly: **a top-level claim on a `program` spec narrows the home slices, not the nixos slice.** `hyprland` shows exactly this — it claims `hosts = [ "khion" "lumi" ]` at the top (narrowing its files/templates) *and* repeats `hosts = [ "khion" "lumi" ]` inside the nixos unit:

```nix
den.aspects.hyprland = program {
  hosts = [ "khion" "lumi" ];              # narrows the home slices below
  nixos = { pkgs, ... }: [
    {
      hosts = [ "khion" "lumi" ];          # the nixos unit claims for itself
      programs.hyprland.enable = true;
    }
  ];
  files = [ { dest = ".config/hypr/hyprland.lua"; src = "..."; } ];
};
```

Why the split at all: home slices need `user` in scope, the nixos slice must resolve with no user. `program` reads `host` (and, for home, `user`) lazily from each class module's own args and resolves there, which is what lets the call stay a bare `program { ... }` with no `{ host, user }:` wrapper. An untagged spec narrows on nothing, so it resolves with no context read at all — that's why `kitty` works globally with nothing threaded in.

## The shipped aspects, by shape

- **`kitty`** — home-only, fully untagged (global). The minimal case.
- **`audio`** — host-only. Just a `nixos` slice claimed to two hosts. See [make an aspect host-only](../how-to/host-only-aspect.md).
- **`hyprland`** — home slices *and* a host-only nixos slice, both host-claimed.
- **`notion-sync`** — a nixos slice that's global except one host-narrowed field. See [narrow a single field](../how-to/narrow-a-single-field.md).

## See also

- [The authoring surface](authoring-surface.md) — what a unit is.
- [Doors and `program` args](../reference/doors-and-program-args.md) — the exact spec fields and door signatures.
- [Make an aspect host-only](../how-to/host-only-aspect.md) and [narrow a single field](../how-to/narrow-a-single-field.md) — the two most common shapes.
