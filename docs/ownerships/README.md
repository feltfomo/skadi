# Ownerships

Ownerships is the targeting layer in front of plain Nix configuration values. A unit declares who owns it; the resolver composes nested claims, validates the resulting leaves, selects those matching one build context, and structurally merges the survivors.

Ownerships runs before the NixOS or Home Manager module system. It does not know option types, priorities, `mkDefault`, `mkForce`, or submodule merge rules.

## Start here

Most skadi aspects should use `program`:

```nix
{
  program,
  rootPath,
  ...
}:
{
  den.aspects.example = program {
    hosts = [ "khion" ];
    pkg = pkgs: pkgs.example;
    files = [
      {
        src = "${rootPath}/configs/example/config.toml";
        dest = ".config/example/config.toml";
      }
    ];
  };
}
```

Use the injected `resolve` or `resolveSystem` only when Program's bounded fields do not fit the configuration.

## Core model

```nix
[
  { packages = [ pkgs.git ]; }
  {
    hosts = [ "khion" ];
    packages = [ pkgs.nvtopPackages.nvidia ];
  }
  {
    users = [ "feltfomo" ];
    programs.helix.enable = true;
  }
]
```

Each config-bearing attrset is a **unit**. A unit may have ownership claims, children, identity metadata, and an optional merge profile. No claim means global ownership.

The ordinary outcomes are:

- **selected**: the leaf applies and contributes to merge;
- **inactive**: the claim is valid but does not match this context;
- **impossible**: the effective claim cannot match the modeled roster;
- **conflict**: selected co-owners provide incompatible values.

Inactive is not an error. Impossible declarations fail before selection, even when the current context would not have selected them.

## Documentation

- [Usage](USAGE.md)
- [Architecture](architecture.md)
- [Merge and provenance](merge-and-provenance.md)
- [Rosters and extension](rosters-and-extension.md)
- [Trace and matrix inspection](inspection.md)
- [Reference](reference.md)

## Source map

| File | Responsibility |
| --- | --- |
| `surface.nix` | Author syntax, scope guards, and public resolver constructors. |
| `resolve.nix` | Bind descriptors, relations, registries, stages, and rosters. |
| `engine.nix` | Compose, validate, select, trace, and merge pipeline. |
| `axes.nix` | Claims, descriptors, aliases, scopes, and relation registrations. |
| `roster.nix` | Descriptor-driven standalone roster construction. |
| `merge.nix` | Tracked merge, profiles, locks, and provenance. |
| `matrix.nix` | Read-only projection across modeled contexts. |
| `default.nix` | Export the supported facade. |

## Supported facade

`default.nix` exports:

- `mkResolve`, `mkResolveSystem`;
- trace, matrix, strict, and profiled siblings;
- `translate`, `claimKeys`;
- `define`, `toRoster`, `mkRoster`.

Skadi aspect authors normally receive only `program`, `resolve`, and `resolveSystem` as module arguments. The remaining constructors are library, test, audit, and extension surfaces.

## Verification

```fish
nix fmt
nix flake check -L
```
