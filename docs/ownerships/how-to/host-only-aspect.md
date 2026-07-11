# Make an aspect host-only

**Goal:** own a nixos slice — a system package, a service, a compositor — for a specific set of hosts, with no per-user narrowing.

Use `program`'s `nixos` path. It resolves host-only (the mechanism is `resolveSystem`; see [the two doors](../explanation/doors-and-program.md)), so a `users` claim anywhere in that slice is a hard error, which is exactly what you want for host-wide config.

## Recipe

`spec.nixos` is a function `{ pkgs, config, ... }: [ units ]`. Put the host claim on the unit it belongs to:

```nix
{ program, ... }:
{
  den.aspects.audio = program {
    nixos = { pkgs, ... }: [
      {
        hosts = [ "khion" "lumi" ];
        environment.systemPackages = [ pkgs.pavucontrol ];
      }
    ];
  };
}
```

This is the real `audio` aspect. On khion and lumi the unit applies; on any other host it's [inactive](../explanation/the-three-outcomes.md#1-inactive--silent) and that host collapses to `{}` for it — no error, nothing to guard.

## Notes that matter

- **The claim goes on the returned nixos unit, not the spec top level.** A top-level claim on the `program` spec narrows the *home* slices (`files`/`templates`/`pkg`), not `spec.nixos`. If you also have home slices to host-narrow, claim both places — that's what `hyprland` does. See [where the claims land](../explanation/doors-and-program.md#where-the-claims-land).
- **Never put `users` / `exceptUsers` in a nixos slice.** A host-only slice binds no user, so it can't narrow on one. Doing so throws at author time — see [`assertNoUserClaim`](../reference/errors.md#author-time-surface).
- **`config` is threaded in.** If your slice needs to read other NixOS config, take it from the function args: `nixos = { config, ... }: [ ... ]`. Don't reach for a module `config` from outside the function.

## See also

- [The two doors and `program`](../explanation/doors-and-program.md) — why the nixos path is host-only.
- [Narrow a single field](narrow-a-single-field.md) — when most of the slice is global and only one field is host-specific.
- [Doors and `program` args](../reference/doors-and-program-args.md#program-spec) — the `nixos` field shape.
- [Error catalog](../reference/errors.md) — the host-only user-claim error.
