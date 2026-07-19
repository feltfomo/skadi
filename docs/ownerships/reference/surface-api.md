# Surface API

All functions below come from `surface.nix` unless noted.

| Function | Result |
| --- | --- |
| `mkResolve roster units rawCtx` | user-scope merged value |
| `mkResolveSystem roster units rawCtx` | system-scope merged value |
| `mkResolveStrict roster units rawCtx` | user resolve after validating the context tuple |
| `mkResolveSystemStrict roster units rawCtx` | system resolve after validating the host |
| `mkResolveTrace roster units rawCtx` | user resolve plus trace/provenance |
| `mkResolveSystemTrace roster units rawCtx` | system resolve plus trace/provenance |
| `mkResolveMatrix roster { units; contextFor ? ...; }` | host/user fleet report |
| `mkResolveSystemMatrix roster { units; contextFor ? ...; }` | host fleet report |
| `mkResolveProfiled profileArgs roster units rawCtx` | user resolve with merge profiles enabled |
| `mkResolveSystemProfiled profileArgs roster units rawCtx` | system resolve with merge profiles enabled |
| `translate unit` | engine-shaped claim tree node |
| `define.<axis>` | standalone declaration constructor |
| `toRoster declarations` | descriptor-projected roster |
| `mkRoster descriptors` | custom descriptor-driven roster factory |

`resolveWith` and `engineArgsFor` live in `resolve.nix` and are lower-level.

## `program` split

`program` turns one spec into home-manager, hjem, and optional NixOS slices.

Home fields include `pkg`, `imports`, `files`, `templates`, and `noctaliaConfig`. Spec-level claims narrow these slices. `files` and `templates` may carry per-entry claims.

`nixos = { pkgs, config, ... }: [ unit ]` returns a separate system-scope unit list. Top-level spec claims don't flow into it.

The flake currently injects only `program`, `resolve`, and `resolveSystem` as aspect module args. Trace, matrix, strict, and profiled constructors are library surfaces for tests, audits, or future wiring.
