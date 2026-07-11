# Narrow a single field

**Goal:** keep an aspect global, but make *one* field apply to only some hosts (or users) — without splitting the aspect in two or wrapping the whole thing in a claim.

Emit two units: a global one for the shared config, and a narrowed one for just the field that differs. They merge on the hosts where both apply.

## Recipe

This is the real `notion-sync` shape — the service is global, but `keepWarm` is only wanted on khion:

```nix
{ program, ... }:
{
  den.aspects.notion-sync = program {
    nixos = { config, ... }: [
      {
        # global: every host that pulls this aspect gets the service
        imports = [ ... ];
        services.notion-sync.enable = true;
      }
      {
        # khion only: one extra field, layered on top
        hosts = [ "khion" ];
        services.notion-sync.keepWarm.enable = true;
      }
    ];
  };
}
```

On khion, both units survive and merge: the shared attrset unions, so khion gets the service *and* `keepWarm`. On lumi, the second unit is [inactive](../explanation/the-three-outcomes.md#1-inactive--silent) and only the global service applies. No conditional, no `lib.mkIf`, no host lookup.

## Why this over a `when` or an `mkIf`

The field's owner *is* the narrow — it's stated once, declaratively, on the unit that carries the field. There's no predicate to evaluate and no imperative branch to read the build host. The merge does the layering, and a scalar clash between the two units (if both set the same leaf differently) would surface as a loud [conflict](../explanation/the-three-outcomes.md#3-conflict--loud-error) rather than a silent last-wins.

## The same shape at user scope

For a per-user field on an otherwise-global home aspect, narrow a single `files` / `templates` entry with a `users` claim instead of splitting nixos units:

```nix
files = [
  { dest = ".config/app/base.conf";  src = "..."; }                    # everyone
  { dest = ".config/app/extra.conf"; src = "..."; users = [ "feltfomo" ]; }  # one user
];
```

Per-entry claims on `files`/`templates` are exactly for this. See [where the claims land](../explanation/doors-and-program.md#where-the-claims-land).

## See also

- [The two doors and `program`](../explanation/doors-and-program.md) — spec-level vs per-entry vs per-nixos-unit claims.
- [The three outcomes](../explanation/the-three-outcomes.md) — inactive and conflict, the two you rely on here.
- [Make an aspect host-only](host-only-aspect.md) — when the *whole* slice is host-specific.
