# scoped — register config to its hosts & users

den threads `{ host, user }` into every class module, so anything being built
already knows *who* and *where* it's for. `scoped` turns that into a selector:
say on the thing which hosts/users it's for, instead of forking files or keeping
base + override lists. Untagged reaches everyone; a selector only ever narrows.

There is no registry and no second pass. At build time den calls your aspect
with its `{ host, user }`; `for` / `resolve` compare the selector to that
context; a hit returns the value, a miss returns `{}` (or drops the spec field).
den merges `{}` as identity, so a missed aspect contributes nothing — no file,
no package, no option. That's the whole mechanism.

## How it reaches you

`scoped` is a module arg, sitting next to `lib` and `rootPath`. So is `program`
— the home-spec builder that calls `scoped` for you. Pull what you need from the
aspect's args:

```nix
{ scoped, program, rootPath, ... }:
{
  den.aspects.foo = ...;
}
```

Aspects never `import ../_lib/scoped.nix` and never call `den.lib.*`. `scoped`
and `program` are wired as module args in `flake.nix`.

## The three functions

`scoped` exports `matches`, `for`, and `resolve`. Day to day you'll write `for`
and list entry-keys; `matches` is the primitive underneath.

### `matches { hosts?, users?, when? } ctx -> bool`

True when every field you set holds (they AND together); a field you omit
doesn't constrain. `hosts` / `users` are den entity names — the attr a host or
user is declared under (`"khion"`, `"feltfomo"`). `when ctx -> bool` is the
escape hatch for anything else. You rarely call this directly.

### `for` — gate one value

Bind it once at the top of the aspect, then wrap a block or scalar:

```nix
{ host, user }:
let for = scoped.for { inherit host user; };
in {
  homeManager = for { hosts = [ "khion" ]; } {
    programs.foo.enable = true;
    home.sessionVariables.WHO = user.name;   # closure — reads user directly
  };
}
```

A miss returns `{}`, so an off-selector block merges to nothing. **`for` is
block-only**: its miss is `{}`, which is correct for a module/block but wrong for
a scalar whose real value could legitimately be `{}`.

### `resolve` — filter a whole spec at once

You rarely call this directly; `program` calls it for you. It walks each field:

- **list fields** (`files`, `templates`, `imports`): drop entries whose
  `users` / `hosts` miss, then strip those keys off the survivors. Bare
  (non-attrset) entries are untagged and pass through untouched.
- **a non-list field equal to `{}`**: treated as a `for`-miss and dropped.
- **everything untagged** is kept.

## Two ways to narrow (they compose)

**1. Entry-keys on list fields** — put `hosts` / `users` right on the entry:

```nix
files = [
  { dest = ".config/app/app.conf";   src = base; }                      # everyone
  { dest = ".config/app/khion.conf"; src = big;  hosts = [ "khion" ]; } # khion only
];
```

**2. `for` on scalars and blocks** — a `pkg`, a whole `homeManager` block, a
`nixos` slice:

```nix
pkg = for { users = [ "feltfomo" ]; } (p: p.kitty);   # feltfomo only; miss drops pkg
```

## Bind the right context

- user / home aspects take `{ host, user }`.
- host / system (nixos) aspects take `{ host }`.

Binding `user` on a host aspect fans it out per-user and vanishes on a userless
host. Bind only what the aspect actually reads.

## Examples (from the tree)

**Untagged — reaches everyone, so no context function, just call `program`:**

```nix
{ program, rootPath, ... }:
{
  den.aspects.kitty = program {
    pkg = pkgs: pkgs.kitty;
    files = [
      { dest = ".config/kitty/kitty.conf"; src = "${rootPath}/configs/kitty/kitty.conf"; }
    ];
    templates = [
      { name = "kitty.conf"; templateFile = "${rootPath}/configs/kitty/themes/skadi.conf"; }
    ];
  };
}
```

**Narrowed — `for` gates the whole aspect, `program` builds the home slices, the
body still reads host/user by closure:**

```nix
{ scoped, program, rootPath, ... }:
{
  den.aspects.hyprland =
    { host, user }:
    let for = scoped.for { inherit host user; };
    in
    # real machines only. off-selector (e.g. the vm host) collapses the aspect
    # to {}, so the compositor closure never reaches the installer-test VM.
    for { hosts = [ "khion" "lumi" ]; } (
      let
        base = program {
          inherit host user;
          files = [
            { dest = ".config/hypr/hyprland.lua"; src = "${rootPath}/configs/hypr/hyprland.lua"; }
            # ... add `users = [ ... ];` to a file to give it to only those users
          ];
        };
      in
      {
        nixos = hyprNixos;                 # compositor + portal
        inherit (base) homeManager hjem;   # daemon + config files
      }
    );
}
```

`matches` short-circuits a null host to `false`, so a hostless build is safe —
the aspect just collapses to `{}`.

**System aspect — binds `{ host }`, gates its `nixos` slice:**

```nix
{ scoped, ... }:
{
  den.aspects.audio =
    { host }:
    let for = scoped.for { inherit host; };
    in {
      nixos = for { hosts = [ "khion" "lumi" ]; } (
        { pkgs, ... }: { environment.systemPackages = [ pkgs.pavucontrol ]; }
      );
    };
}
```

A system package (not a home aspect) so it serves every user on the host — a
home aspect on one user would miss the others.

## Invariants — don't break these

- **Untagged reaches everyone.** A selector only narrows; it never adds reach.
- **A gated block reads host/user by closure, never through `imports`.** den
  drops `{ host, user }` at the import boundary. Keep the gated body inline;
  compose a base via `imports`, the gated body via `config` / the return value.
- **Bind the context the aspect uses** — `{ host, user }` for home aspects,
  `{ host }` for system aspects.
- **`for` is block-only** (miss → `{}`). A scalar whose real value could be `{}`
  needs a tagged wrapper, which doesn't exist yet — flag it rather than lean on
  the `{}` sentinel.
- **den internals stay in `_lib/den.nix`.** Aspects call `scoped.*` / `lib.*`
  and take `program` as an arg — never `den.lib.*`, never `import` the libs
  directly.

## The den boundary (for the curious)

The standalone / filtered builds the installer uses — drop an aspect, build a
host off-tree — live behind `_lib/den.nix`, the one file allowed to touch den's
guts (`den.hosts`, `den.lib.resolveEntity`, `aspects.resolve`, `h.instantiate`).
Config authors never touch it. It exists so a den version bump lands in one
place instead of scattered across aspects.
