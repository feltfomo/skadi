# Axiom laws and laziness

Axiom is designed for Nix values that may contain functions, derivations, secrets, throwing fields, or expensive computations. These guarantees are shallow: callers still decide what their callbacks inspect.

## Validation laws

### Success has a value

A successful result has empty diagnostics and a `value` field.

```nix
(validation.success value).diagnostics == [ ]
```

### Failure has no usable value

A failed result contains diagnostics and omits `value`. Do not read `result.value` before checking or finishing the result.

### Mapping preserves failure

```nix
validation.map f (validation.failure diagnostics)
```

preserves diagnostics and does not call `f`.

### Binary accumulation is ordered

`validation.map2 f left right` concatenates left diagnostics before right diagnostics. It calls `f` only when both results succeed.

### Sequence accumulation is ordered

`validation.sequence` and `validation.traverse` preserve input order for successful values and diagnostics.

### Diagnostics remain opaque

Validation checks only that diagnostic collections are lists. It does not inspect, render, deduplicate, sort, or force diagnostic members beyond what list operations require.

## Schema laws

### The schema specification is closed

The top-level schema specification accepts only `fields`, `onRecord`, `allowUnknown`, `onUnknown`, and `order`. Field descriptors use `required`, `default`, `validate`, `normalize`, `onMissing`, and `onInvalid`. Extra field-descriptor attributes are not part of the public contract and should not be relied on.

### Closed schemas require unknown-field policy

When `allowUnknown = false`, `onUnknown` is required. Unknown names are sorted by Nix attr-name order and diagnosed before declared fields.

### Explicit field order is exact

When supplied, `order` must contain every declared field exactly once. It determines field diagnostic order and normalized-field construction order.

### Defaults follow the same value path

Defaults are validated and normalized. A rejecting default invokes `onInvalid` just like a present value.

### Optional absence is omission

An optional field with no default is omitted from the normalized result.

### Open schemas overlay normalized fields

With `allowUnknown = true`, the original record is preserved and normalized declared fields are overlaid. This keeps extension fields while allowing known metadata to be normalized.

### Schema inspection is shallow

Schema itself checks the input record and field presence. It does not recursively traverse values. A field's `validate` and `normalize` functions are the forcing boundary.

For example:

```nix
payload = throw "forced payload";

payloadField = { };
```

accepts and preserves the payload without forcing it. By contrast:

```nix
payloadField.validate = builtins.isAttrs;
```

must evaluate the payload enough to determine its outer type.

## Registry laws

### Every registration is diagnosed

`diagnosticsFor` is called for every registration in input order.

### Malformed registrations are not keyed

A registration whose diagnostic list is non-empty is excluded from `keyOf` and duplicate grouping. This allows a safe shape check to guard later metadata access.

### Valid registrations are keyed for duplicate detection

`keyOf` is called for each registration that has no registration diagnostics, even when a different valid registration later creates a duplicate.

### Duplicate diagnostics are deterministic

Registration diagnostics come first in input order. Duplicate diagnostics follow in sorted key order.

### Ordering is deterministic on success

A successful compiled registry sorts registrations with `less`. The caller is responsible for a stable total ordering suitable for its domain. A common rule is priority followed by identity.

### Implementations may remain lazy

Registry mechanics need only the fields read by `diagnosticsFor`, `keyOf`, and `less`. Function bodies and unrelated payload fields remain lazy unless those callbacks inspect them.

## Requirements laws

### Requirement values are strings

Required and provided collections must be lists of strings. Normalization removes duplicates while preserving first occurrence order.

### Missing order follows required order

`evaluate` filters normalized requirements against provided values, so the caller's requirement order is preserved in `missing`.

### Candidate order is preserved

`observe` emits entries, qualified entries, and rejected entries in candidate order. It does not rank candidates; combine it with a registry when ranking matters.

### Disabled candidates do not provide

`enabled` is called for every candidate. `providedBy` is called only when the candidate is enabled. A disabled candidate reports no provided capabilities and every normalized requirement as missing.

### Requirements observe rather than throw

Unsatisfied requirements are data. The caller decides whether no qualified candidate is an error, a fallback condition, or an expected empty result.

## Phase laws

### Phase names are closed and unique

The declared phase list is the complete accepted vocabulary and must contain unique strings.

### Every registration is projected

`phaseOf` is called for every registration. It should be shallow and safe on malformed input.

### Runnable checks follow phase checks

`runnable` is called only when `phaseOf` returned a known string. Unknown registrations therefore do not need a runnable shape.

### Diagnostic categories have stable precedence

Unknown-phase diagnostics are emitted before invalid-runnable diagnostics. Registration order is preserved within each category.

### Registration order is preserved per phase

`byName.${phase}` and `for phase` preserve the original order of registrations assigned to that phase.

### Run functions are never invoked

A typical `runnable` predicate checks `builtins.isFunction registration.run`. This evaluates the field enough to identify a function but does not call its body.

## Identity laws

Identity precedence is label, then source, then path. `render` invokes only the renderer for the selected form. A fallback is returned unchanged when the identity is empty.

Identity is not safe rendering. If a caller supplies a label, source, path component, renderer, or fallback that forces unsafe data, Axiom does not hide that mistake.

## Tagged-value laws

- `tagged.mk` requires a non-empty string tag.
- `tagged.map` preserves the tag and maps only the payload.
- `tagged.match` selects exactly one named handler or the default handler.
- `tagged.expect` is an assertion boundary and throws on a different variant.
- Tagged payloads are not recursively inspected.

The internal marker is an implementation detail. Construct tagged values only with `tagged.mk`.

## Canonical-name laws

Canonical helpers accept strings and reject empty components. They only join components; they do not normalize case, filesystem separators, `.` segments, `..` segments, URI escaping, or Unicode.

Use them for identities whose components are already validated by the caller. Use a domain-specific path normalizer for filesystem containment.

## Poison-value testing

When adding an Axiom integration, place throwing values behind fields that must remain lazy:

```nix
poison = throw "forced poison";

registration = {
  name = "example";
  priority = 10;
  implementation = poison;
};
```

Then force only the intended projection:

```nix
compiled = registry.compile { ... };

assert compiled.value.keys == [ "example" ];
```

Useful poison targets include:

- derivation `drvPath` and `outPath`;
- secret-bearing attrsets;
- inactive candidate capabilities;
- unselected implementation functions;
- callback bodies that should be checked but not called;
- provenance and descriptive metadata;
- successful validation payloads when only diagnostics are needed.

## Callback checklist

Before adding a callback, ask:

1. Which fields must it force?
1. Can malformed input reach it?
1. Does a prior validation result guard it?
1. Is its diagnostic value safe to construct without traversing payloads?
1. Does its ordering affect visible errors?
1. Does it throw a direct-use error or return a domain diagnostic?
1. Is there a poison-value test for the boundary?

## Error boundary

Axiom direct-use errors begin with `axiom:` and indicate malformed library integration. Ordinary domain errors should be produced through caller callbacks or observations and rendered by the consuming subsystem.

Do not expose an Axiom direct-use error as if it were a normal end-user validation failure. Fix the integration that violated the Axiom contract.
