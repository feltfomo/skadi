# Axiom recipes

These recipes show how the primitives compose without tying Axiom to one diagnostic representation.

## A caller-owned diagnostic type

Axiom treats diagnostics as opaque values. A small library can use records:

```nix
problem = code: message: {
  inherit code message;
};

failProblems =
  diagnostics:
  throw (
    lib.concatMapStringsSep "\n"
      (diagnostic: "example/${diagnostic.code}: ${diagnostic.message}")
      diagnostics
  );
```

A subsystem already using Krisis can return Krisis diagnostic records from the same callbacks and pass its reporter's `fail` method to `validation.finish`.

## Validate and normalize a plugin record

```nix
pluginSchema = axiom.schema.compile {
  order = [
    "name"
    "priority"
    "enabled"
    "capabilities"
    "run"
  ];

  fields = {
    name = {
      required = true;
      validate = value: builtins.isString value && value != "";
      normalize = lib.toLower;
      onMissing = _plugin: problem "name-missing" "plugin name is required";
      onInvalid = _plugin: _value: problem "name-invalid" "plugin name must be a non-empty string";
    };

    priority = {
      default = 100;
      validate = builtins.isInt;
      onInvalid = plugin: _value:
        problem "priority-invalid" "${plugin.name or "unlabeled plugin"} priority must be an integer";
    };

    enabled = {
      default = true;
      validate = builtins.isBool;
      onInvalid = _plugin: _value: problem "enabled-invalid" "enabled must be a boolean";
    };

    capabilities = {
      default = [ ];
      validate = value: builtins.isList value && lib.all builtins.isString value;
      normalize = lib.unique;
      onInvalid = _plugin: _value:
        problem "capabilities-invalid" "capabilities must be a list of strings";
    };

    run = {
      required = true;
      validate = builtins.isFunction;
      onMissing = _plugin: problem "run-missing" "plugin run function is required";
      onInvalid = _plugin: _value: problem "run-invalid" "plugin run must be a function";
    };
  };

  onRecord = _value: problem "plugin-type" "plugin must be an attribute set";
  onUnknown = name: _value: problem "field-unknown" "unknown plugin field '${name}'";
};
```

`order` makes diagnostic order part of the caller's contract rather than relying on sorted attr names.

## Compile schema-checked registrations

Use schema diagnostics as the registry's registration diagnostics. `keyOf` will only receive registrations that passed the schema checks.

```nix
compilePlugins =
  plugins:
  axiom.registry.compile {
    registrations = plugins;
    diagnosticsFor = plugin: (pluginSchema plugin).diagnostics;
    keyOf = plugin: plugin.name;
    less = left: right:
      if left.priority == right.priority
      then builtins.lessThan left.name right.name
      else left.priority < right.priority;
    onDuplicate = name: _plugins:
      problem "name-duplicate" "plugin name '${name}' is registered more than once";
  };
```

This arrangement deliberately does not use the normalized schema value as the registry registration. Registry validates and indexes the supplied registrations; if later work requires normalized registrations, normalize before registry compilation or retain schema results in a caller-owned preparation step.

One explicit preparation pattern is:

```nix
preparedResult = axiom.validation.traverse pluginSchema plugins;

registryResult = axiom.validation.map
  (prepared:
    axiom.registry.compile {
      registrations = prepared;
      keyOf = plugin: plugin.name;
      less = left: right: left.priority < right.priority;
      onDuplicate = name: _plugins:
        problem "name-duplicate" "duplicate plugin '${name}'";
    })
  preparedResult;
```

Because the mapped function returns another validation result, finish the outer and inner results separately or add a caller-local flatten helper:

```nix
flatten = result:
  axiom.validation.finish axiom.validation.failure result;

compiled = flatten registryResult;
```

For most subsystem code, a single preparation function that returns one final validation result is clearer than deeply nesting generic combinators.

## Select an implementation by requirements

Assume `compiled` is a successful registry value:

```nix
observation = axiom.requirements.observe {
  required = [
    "render"
    "reload"
  ];
  candidates = compiled.ordered;
  enabled = plugin: plugin.enabled;
  providedBy = plugin: plugin.capabilities;
};
```

Select the first candidate in registry order:

```nix
selectedResult =
  if observation.qualified == [ ] then
    axiom.validation.failure [
      (problem "plugin-unavailable" "no enabled plugin provides render and reload")
    ]
  else
    axiom.validation.success (builtins.head observation.qualified).candidate;
```

Rejected observations remain useful for debugging or richer domain diagnostics:

```nix
rejections = map
  (entry: {
    inherit (entry.candidate) name;
    inherit (entry) enabled missing;
  })
  observation.rejected;
```

Do not render candidates or capability payloads inside Axiom callbacks unless those values are already known safe.

## Compile ordered hooks

```nix
hookResult = axiom.phases.compile {
  names = [
    "prepare"
    "validate"
    "apply"
  ];
  registrations = hooks;
  phaseOf = hook:
    if builtins.isAttrs hook && hook ? phase && builtins.isString hook.phase
    then hook.phase
    else null;
  runnable = hook: hook ? run && builtins.isFunction hook.run;
  onUnknown = hook: phase:
    problem "phase-unknown" (
      if phase == null
      then "hook is missing a known phase"
      else "unknown hook phase '${phase}'"
    );
  onInvalid = _hook: phase:
    problem "run-missing" "hook in phase '${phase}' must provide run";
};
```

Run phases only after finishing compilation:

```nix
hookPlan = axiom.validation.finish failProblems hookResult;

runPhase = name: value:
  builtins.foldl'
    (current: hook: hook.run current)
    value
    (hookPlan.for name);

prepared = runPhase "prepare" input;
validated = runPhase "validate" prepared;
output = runPhase "apply" validated;
```

Axiom groups registrations; the caller owns execution semantics, state threading, exception context, and whether a phase stops or accumulates failures.

## Preserve identity without choosing presentation

```nix
pluginIdentity = axiom.identity.mk {
  label = plugin.label or null;
  source = plugin.source or null;
  path = [
    "plugins"
    plugin.name
  ];
};

shown = axiom.identity.render {
  identity = pluginIdentity;
  renderLabel = label: "plugin '${label}'";
  renderSource = source: "plugin at ${source}";
  renderPath = path: axiom.canonical.path path;
  fallback = "anonymous plugin";
};
```

The producer records identity evidence. The reporting boundary chooses how each form appears.

## Model an explicit outcome

```nix
select = candidates:
  if candidates == [ ]
  then axiom.tagged.mk "missing" null
  else axiom.tagged.mk "selected" (builtins.head candidates);

outcome = select observation.qualified;

result = axiom.tagged.match {
  selected = entry: axiom.validation.success entry.candidate;
  missing = _value:
    axiom.validation.failure [
      (problem "selection-empty" "no candidate qualified")
    ];
} outcome;
```

Tagged values are useful when variants are part of an internal protocol. They are not a replacement for validation accumulation: use validation when several independent diagnostics should survive together.

## Canonical registration keys

```nix
keyOf = plugin:
  axiom.canonical.qualified {
    namespace = plugin.namespace;
    name = plugin.name;
  };
```

For more than two components:

```nix
key = axiom.canonical.join "/" [
  system
  subsystem
  registration
];
```

Canonical helpers validate shape and reject empty parts; they do not normalize filesystem paths or remove `.` and `..` segments.

## Keep ordinary errors domain-owned

A final boundary might look like:

```nix
compiledPlugins = axiom.validation.finish reporter.fail (
  compilePlugins plugins
);
```

The resulting error should be named and rendered by the plugin subsystem. Do not catch Axiom's direct-use errors and present them as ordinary plugin diagnostics; direct-use errors indicate a bug in the library integration itself.
