# Axiom API reference

Import the library once:

```nix
axiom = import ./modules/_lib/axiom { inherit lib; };
```

All functions are curried Nix functions unless an attrset argument is shown.

## `validation`

Validation results use `{ diagnostics = [ ]; value = value; }` for success and `{ diagnostics = diagnostics; }` for failure. A failed result has no `value` field.

### `validation.success value`

Construct a successful result.

```nix
validation.success 42
# { diagnostics = [ ]; value = 42; }
```

### `validation.failure diagnostics`

Construct a failed result. `diagnostics` must be a list and should be non-empty.

```nix
validation.failure [ "invalid name" ]
```

### `validation.fromDiagnostics diagnostics value`

Return success when `diagnostics` is empty, otherwise failure. `value` remains lazy when diagnostics exist.

```nix
validation.fromDiagnostics problems normalized
```

### `validation.map f result`

Apply `f` to a successful value. Preserve a failed result without calling `f`.

```nix
validation.map (value: value + 1) (validation.success 1)
```

### `validation.map2 f left right`

Combine two successful values. If either result failed, concatenate left diagnostics followed by right diagnostics and do not call `f`.

```nix
validation.map2 (name: port: { inherit name port; }) nameResult portResult
```

### `validation.sequence results`

Turn a list of results into one result containing a list of values. Diagnostics accumulate in result order.

```nix
validation.sequence [ firstResult secondResult thirdResult ]
```

### `validation.traverse f values`

Equivalent to `validation.sequence (map f values)`.

```nix
validation.traverse validateEntry entries
```

### `validation.collect groups`

Flatten a list of diagnostic lists while preserving group and item order.

```nix
validation.collect [ shapeDiagnostics duplicateDiagnostics ]
```

### `validation.optional condition diagnostic`

Return `[ diagnostic ]` when `condition` is true and `[ ]` otherwise. The condition must be a boolean. A false condition does not force the diagnostic.

```nix
validation.optional (name == "") "name must not be empty"
```

### `validation.finish fail result`

Return a successful value or call `fail diagnostics` for a failed result.

```nix
validation.finish reporter.fail result
```

`finish` is the intended boundary between generic accumulation and caller-owned failure policy.

## `schema`

### `schema.compile specification`

Compile a record schema into a validator function.

```nix
validate = schema.compile {
  fields = { ... };
  onRecord = value: diagnostic;
  onUnknown = name: value: diagnostic;
  allowUnknown = false;
  order = null;
};

result = validate record;
```

The specification fields are:

| Field | Required | Meaning |
| -------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `fields` | yes | Attrset of field specifications. |
| `onRecord` | yes | Called as `value: diagnostic` when the input is not an attrset. |
| `allowUnknown` | no | Preserve unknown fields instead of diagnosing them. Defaults to `false`. |
| `onUnknown` | for closed schemas | Called as `name: value: diagnostic` for each unknown field. |
| `order` | no | Exact list of all declared field names, used for diagnostic and normalization order. Defaults to sorted attr names. |

A field specification accepts:

| Field | Meaning |
| ----------- | -------------------------------------------------------------------------------- |
| `required` | Whether absence is an error. Defaults to `false`. |
| `default` | Value used when the field is absent. A default takes precedence over `required`. |
| `validate` | Predicate called with the present or default value. Defaults to always true. |
| `normalize` | Transformation applied after validation. Defaults to identity. |
| `onMissing` | Called as `record: diagnostic` for an absent required field. |
| `onInvalid` | Called as `record: value: diagnostic` after predicate rejection. |

A required field must define `onMissing` unless it has a default. A rejecting validator must have `onInvalid`; otherwise Axiom reports malformed schema use.

Defaults are validated and normalized. Optional fields without a value or default are omitted. Closed schemas return only declared fields. Open schemas return the original record with normalized declared fields overlaid.

Unknown-field diagnostics appear first in sorted unknown-name order. Declared-field diagnostics follow `order`.

## `identity`

### `identity.mk { label ? null, source ? null, path ? [ ] }`

Construct a closed identity record. `label` and `source` must be strings or null. `path` must be a list of strings. Unknown fields are rejected.

### `identity.primary identity`

Choose the first available identity in this order:

1. non-null `label`;
1. non-null `source`;
1. non-empty `path`;
1. `null`.

The selected result is `{ kind = "label" | "source" | "path"; value = ...; }`.

### `identity.render { identity, renderLabel, renderSource, renderPath, fallback }`

Render only the selected identity form. The three renderers must be functions. `fallback` is returned unchanged when no identity exists.

```nix
identity.render {
  identity = identity.mk { source = "modules/example.nix"; };
  renderLabel = label: label;
  renderSource = source: "at ${source}";
  renderPath = path: canonical.path path;
  fallback = "anonymous";
}
```

## `requirements`

Requirements operate on lists of strings.

### `requirements.normalize values`

Validate that `values` is a list of strings and remove duplicates while preserving first occurrence order.

### `requirements.evaluate required provided`

Return:

```nix
{
  required = normalizedRequired;
  provided = normalizedProvided;
  missing = requiredValuesNotProvided;
  satisfied = missing == [ ];
}
```

Required order determines `missing` order.

### `requirements.observe { required, candidates, providedBy, enabled ? (_: true) }`

Evaluate requirements across candidates in input order.

Each observation entry contains:

```nix
{
  candidate = originalCandidate;
  enabled = true;
  required = [ ... ];
  provided = [ ... ];
  missing = [ ... ];
  satisfied = true;
}
```

The result contains `entries`, `qualified`, and `rejected`. Disabled candidates are rejected, have no provided values, report all required values as missing, and do not call `providedBy`.

## `registry`

### `registry.compile arguments`

```nix
registry.compile {
  registrations = [ ... ];
  keyOf = registration: string;
  diagnosticsFor = registration: [ ... ];
  less = left: right: boolean;
  onDuplicate = key: registrations: diagnostic;
}
```

Arguments:

| Field | Required | Meaning |
| ---------------- | -------- | -------------------------------------------------------------------------- |
| `registrations` | yes | Registration list. |
| `keyOf` | yes | Return a string key for a valid registration. |
| `diagnosticsFor` | no | Return a diagnostic list for one registration. Defaults to no diagnostics. |
| `less` | no | Ordering predicate. Defaults to key ordering. |
| `onDuplicate` | yes | Return one diagnostic for a duplicated valid key. |

Registration diagnostics are accumulated in input order. Registrations with diagnostics are excluded from key extraction and duplicate grouping. Duplicate diagnostics follow registration diagnostics and are ordered by duplicate key.

On success, `value` contains:

| Field | Meaning |
| ------------------ | -------------------------------------------- |
| `registrations` | Original registration list. |
| `ordered` | Registrations sorted by `less`. |
| `byKey` | Keyed attrset. |
| `keys` | Keys in sorted registration order. |
| `lookup key` | Registration or `null`. |
| `select predicate` | Sorted registrations matching the predicate. |

A failed result has no compiled registry value.

## `canonical`

### `canonical.join separator parts`

Join a list of non-empty strings. `separator` must be a string and every part must be a string. Empty parts are rejected.

```nix
canonical.join ":" [ "x86_64-linux" "/etc/example" ]
```

### `canonical.qualified { namespace, name, separator ? "/" }`

Join `namespace` and `name` with the separator.

```nix
canonical.qualified {
  namespace = "executor";
  name = "native";
}
# "executor/native"
```

### `canonical.path parts`

Equivalent to `canonical.join "/" parts`.

## `phases`

### `phases.compile arguments`

```nix
phases.compile {
  names = [ "prepare" "apply" ];
  registrations = hooks;
  phaseOf = hook: hook.phase or null;
  runnable = hook: hook ? run && builtins.isFunction hook.run;
  onUnknown = hook: phase: diagnostic;
  onInvalid = hook: phase: diagnostic;
}
```

`names` must be a unique list of strings. Every registration is inspected with `phaseOf`. `runnable` is called only for registrations whose phase is a known string.

Diagnostics are grouped as:

1. unknown-phase diagnostics in registration order;
1. invalid-runnable diagnostics in registration order.

On success, `value` contains:

| Field | Meaning |
| --------------- | ------------------------------------------------------ |
| `order` | Declared phase names. |
| `registrations` | Original registration list. |
| `byName` | Attrset mapping every phase name to its registrations. |
| `for name` | Registrations for a known compiled phase. |

Registration order is preserved inside each phase. Calling `for` with a name outside the compiled phase set is malformed direct use and throws an Axiom error.

## `tagged`

Tagged values have an internal Axiom marker. Construct them with `tagged.mk`; do not imitate their attrset shape manually.

### `tagged.mk tag value`

Construct a tagged value. `tag` must be a non-empty string.

### `tagged.isTagged value`

Return whether `value` is an Axiom tagged value.

### `tagged.tagOf value`

Return its tag or `null`.

### `tagged.has tag value`

Return whether it is tagged with exactly `tag`.

### `tagged.expect tag value`

Return the payload for the expected tag. Throw for untagged values or a different tag.

### `tagged.map f value`

Map the payload while preserving its tag.

### `tagged.match handlers value`

Dispatch to `handlers.${tag}` when present. A named handler receives the payload. Otherwise, an optional `default` handler receives `tag` and payload.

```nix
tagged.match {
  success = value: value;
  failure = diagnostic: throw diagnostic;
  default = tag: _value: throw "unknown tag '${tag}'";
} result
```

Missing handlers, non-function handlers, and untagged values are malformed direct use and throw Axiom errors.
