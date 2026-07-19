# Add an axis or relation

## Add a set axis

Create one `mkSetDescriptor` in `axes.nix`. The descriptor must own author syntax, scope, context projection, and roster projection. The test-only role descriptor in `descriptor-tests.nix` is the reference.

Prove:

- include and exclude syntax;
- standalone declaration and roster projection;
- matching and non-matching selection;
- missing context fails through structured diagnostics;
- every scope restriction, including nested claims;
- production defaults are unchanged when the descriptor is test-only.

Do not edit `compose`, `narrowClaim`, `pipeline`, or `resolve` to add an axis.

## Add a predicate axis

Use `mkPredicateDescriptor` for select-only predicates. It has no roster projection and `ctxKey = null`.

## Add a relation

Register data describing `leftAxis`, `rightAxis`, unknown members, compatibility, and the reason renderer. Keep the generic semantics in `engine.mkRelationCheck`; don't hide a bespoke cross-axis check in one descriptor.

Prove known-compatible, known-incompatible, global-side, empty-side, and unknown-rescue behavior. If replacing an old relation, keep a frozen test oracle until byte parity is demonstrated.

## Add a production axis only on purpose

A descriptor expands the public author language, reserved-key set, context contract, and roster shape. A test-only axis can prove extensibility without making speculative syntax permanent.
