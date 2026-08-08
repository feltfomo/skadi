# Axiom

Axiom is a small functional-machinery library for Nix. It provides reusable building blocks for validated computation, closed schemas, deterministic registries, capability requirements, ordered phases, identity selection, tagged values, and canonical names.

Axiom is for library and subsystem maintainers. It does not define user-facing error wording, render diagnostics, catch arbitrary exceptions, or know anything about NixOS and Home Manager options. Callers supply their own diagnostic values and decide how failures become messages or exceptions.

## Import

```nix
axiom = import ./modules/_lib/axiom { inherit lib; };
```

The import returns eight modules:

```nix
inherit (axiom)
  validation
  schema
  identity
  requirements
  registry
  canonical
  phases
  tagged
  ;
```

## Choose a primitive

| Module | Use it when |
| -------------- | ---------------------------------------------------------------------------------------------------------------- |
| `validation` | Independent checks should accumulate diagnostics before a caller decides whether to stop. |
| `schema` | An attrset has declared fields, defaults, shallow validators, normalization, and caller-owned field diagnostics. |
| `identity` | A value may be named by a label, source, or structured path without binding rendering policy into the producer. |
| `requirements` | Candidates provide named capabilities and must be qualified against a required set. |
| `registry` | Registrations need validation, unique keys, deterministic ordering, lookup, and selection. |
| `canonical` | Stable names or paths must be assembled from validated non-empty string parts. |
| `phases` | Registrations belong to a closed set of named phases and must expose a runnable shape. |
| `tagged` | Several explicit result variants need construction, recognition, mapping, and dispatch. |

## The common result model

`validation`, `schema`, `registry`, and `phases` use the same result shape:

```nix
{
  diagnostics = [ ];
  value = successfulValue;
}
```

A failed result has diagnostics and no `value`:

```nix
{
  diagnostics = [ diagnosticA diagnosticB ];
}
```

Diagnostics are opaque to Axiom. They may be strings, Krisis records, or another caller-owned value.

```nix
result = validation.map2
  (name: port: { inherit name port; })
  (validation.success "api")
  (validation.failure [
    {
      code = "port-missing";
      message = "port is required";
    }
  ]);
```

Finish a result only at the boundary that owns failure policy:

```nix
value = validation.finish
  (diagnostics: throw "example: ${toString (builtins.length diagnostics)} error(s)")
  result;
```

## Quick examples

### Accumulate independent validation

```nix
nameResult =
  if builtins.isString input.name
  then validation.success input.name
  else validation.failure [ "name must be a string" ];

portResult =
  if builtins.isInt input.port
  then validation.success input.port
  else validation.failure [ "port must be an integer" ];

serviceResult = validation.map2
  (name: port: { inherit name port; })
  nameResult
  portResult;
```

If both fields are invalid, both diagnostics are preserved in left-to-right order and the combining function is not called.

### Compile a closed schema

```nix
serviceSchema = schema.compile {
  fields = {
    name = {
      required = true;
      validate = builtins.isString;
      normalize = lib.toLower;
      onMissing = _record: "name is required";
      onInvalid = _record: _value: "name must be a string";
    };

    port = {
      default = 8080;
      validate = builtins.isInt;
      onInvalid = _record: _value: "port must be an integer";
    };

    implementation = { };
  };

  onRecord = _value: "service must be an attribute set";
  onUnknown = name: _value: "unknown service field '${name}'";
};

result = serviceSchema {
  name = "API";
  implementation = request: request;
};
```

The successful value contains `name = "api"`, `port = 8080`, and the original lazy implementation. Closed schemas reject unknown fields through `onUnknown`.

### Build a deterministic registry

```nix
result = registry.compile {
  registrations = plugins;
  keyOf = plugin: plugin.name;
  diagnosticsFor = plugin:
    if builtins.isAttrs plugin && plugin ? name && builtins.isString plugin.name
    then [ ]
    else [ "plugin name must be a string" ];
  less = left: right:
    if left.priority == right.priority
    then builtins.lessThan left.name right.name
    else left.priority < right.priority;
  onDuplicate = name: _plugins: "duplicate plugin '${name}'";
};

pluginsByPriority = result.value.ordered;
jsonPlugin = result.value.lookup "json";
```

Malformed registrations are not passed to `keyOf`. Valid duplicate keys are accumulated with registration diagnostics.

### Match requirements

```nix
observation = requirements.observe {
  required = [ "render" "reload" ];
  candidates = compiledRegistry.ordered;
  enabled = plugin: plugin.enabled or false;
  providedBy = plugin: plugin.capabilities;
};

selected =
  if observation.qualified == [ ]
  then null
  else (builtins.head observation.qualified).candidate;
```

Disabled candidates are rejected without calling `providedBy`.

### Compile phase registrations

```nix
result = phases.compile {
  names = [ "prepare" "apply" ];
  registrations = hooks;
  phaseOf = hook: hook.phase or null;
  runnable = hook: hook ? run && builtins.isFunction hook.run;
  onUnknown = _hook: phase: "unknown phase '${toString phase}'";
  onInvalid = _hook: phase: "phase '${phase}' requires run";
};

prepareHooks = result.value.for "prepare";
```

Registration order is preserved inside each phase. The declared `names` list is the phase order.

### Use tagged variants

```nix
outcome = tagged.mk "selected" value;

text = tagged.match {
  selected = selected: "selected ${selected.name}";
  rejected = reason: "rejected ${reason}";
  default = tag: _value: "unknown outcome ${tag}";
} outcome;
```

Use `tagged.expect` when a boundary requires one exact variant.

## Composition

The modules are intentionally small and composable:

1. `schema` validates each registration while keeping diagnostics in the caller's domain.
1. `registry` excludes malformed registrations from keying, accumulates duplicates, and produces deterministic order and lookup.
1. `requirements` qualifies ordered registrations without touching disabled implementations.
1. `phases` can group a separate extension surface by a closed phase vocabulary.
1. `validation.finish` hands all accumulated failures to the caller's reporter once.

See [Recipes](recipes.md) for complete compositions.

## Error ownership

Axiom throws only for malformed direct use of Axiom itself, such as passing a non-function mapper, declaring duplicate phase names, or constructing an invalid tagged value.

Domain failures belong to the caller:

- Schema invokes `onRecord`, `onUnknown`, `onMissing`, and `onInvalid`.
- Registry invokes `diagnosticsFor` and `onDuplicate`.
- Phases invokes `onUnknown` and `onInvalid`.
- Validation stores diagnostics without inspecting them.
- Requirements returns observations rather than rendering or throwing.

This is why an ordinary Furnish, Program, or Ownerships error should never mention Axiom.

## Laziness

Axiom preserves laziness, but callback design determines the actual forcing boundary. In particular:

- validation mappers are not called after failure;
- schema does not recursively inspect field values, but each field validator may force what it examines;
- registry does not key malformed registrations;
- requirements does not read capabilities from disabled candidates;
- phases checks that `run` is a function but never calls it;
- tagged constructors and maps do not recursively force payloads.

See [Laws and laziness](laws-and-laziness.md) before adding validators around derivations, secrets, callbacks, or large configuration payloads.

## Documentation

- [API reference](reference.md)
- [Recipes](recipes.md)
- [Laws and laziness](laws-and-laziness.md)

## Verification

```fish
nix build .#checks.x86_64-linux.axiom -L
nix fmt
nix flake check -L
```
