# Ownerships

Ownerships is the targeting layer in front of skadi's config values. A unit says who it belongs to on the unit itself. The resolver composes nested claims, rejects contradictions, selects the leaves for one build context, and structurally merges the survivors.

It is not the NixOS module system. It runs before module evaluation and doesn't know option types, priorities, `mkForce`, or submodule merge rules.

## Start here

```nix
[
  { packages = [ pkgs.git ]; } # global
  {
    hosts = [ "khion" ];
    packages = [ pkgs.nvtopPackages.nvidia ];
  }
  {
    users = [ "feltfomo" ];
    files = [ { dest = ".config/example"; src = ./example; } ];
  }
]
```

A config-bearing attrset is a **unit**. `hosts`, `users`, `exceptHosts`, `exceptUsers`, and `when` are claim keys. No claim means global ownership. `children` nests units, and a child can only narrow its parent.

Three ordinary outcomes matter:

- **Selected:** the unit applies to this context and contributes to the merge.
- **Inactive:** the claim is valid but doesn't match this context. The unit disappears silently.
- **Impossible:** the claim can't match any modeled context. Resolution fails before selection.

A fourth failure happens after selection: surviving co-owners can **conflict** while merging.

## Read by task

**Authoring**

- [Authoring surface](explanation/authoring-surface.md)
- [Host-only config](how-to/host-only-aspect.md)
- [Reserved-key collisions and `value`](how-to/value-escape-hatch.md)
- [Claim and unit keys](reference/claim-and-unit-keys.md)

**Understand the machinery**

- [Pipeline and stages](explanation/pipeline-and-stages.md)
- [Merge, provenance, locks, and profiles](explanation/merge-provenance-and-profiles.md)
- [Roster, descriptors, and relations](explanation/roster-relations-and-federation.md)
- [Trace and fleet matrix](explanation/trace-and-matrix.md)

**Extend or inspect it**

- [Run without den](how-to/run-standalone.md)
- [Add an axis or relation](how-to/add-axis-or-relation.md)
- [Inspect a trace or matrix](how-to/inspect-trace-and-matrix.md)
- [Surface API](reference/surface-api.md)
- [Errors and outcomes](reference/errors-and-outcomes.md)
- [Roster shape](reference/roster-shape.md)
- [Glossary](reference/glossary.md)

## Source map

| File | Responsibility |
| --- | --- |
| `modules/_lib/ownerships/surface.nix` | Author syntax, scope guards, public resolve/trace/matrix/profiled doors |
| `modules/_lib/ownerships/engine.nix` | Fixed pipeline, stages, diagnostics, selection trace |
| `modules/_lib/ownerships/axes.nix` | Axis descriptors, polarity sets, aliases, relation registrations |
| `modules/_lib/ownerships/merge.nix` | Shape merge, provenance, locks, named merge profiles |
| `modules/_lib/ownerships/matrix.nix` | Read-only fleet projection and host diffs |
| `modules/_lib/ownerships/roster.nix` | Descriptor-driven standalone roster construction |
| `modules/_lib/ownerships/resolve.nix` | Roster to registry/stages, strict context validation |
| `modules/_lib/ownerships/safe-render.nix` | Diagnostics that don't force packages or secret-backed values |
| `modules/_lib/program.nix` | skadi's packages/files/templates front door |
| `modules/_lib/den.nix` | The only den-internals boundary and federated roster adapter |

The permanent gate is `nix fmt`, then `nix flake check`.
